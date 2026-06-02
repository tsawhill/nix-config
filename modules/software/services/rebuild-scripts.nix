{
  config,
  pkgs,
  lib,
  ...
}:

let
  keepRoots = 5; # number of per-host deploy GC roots to retain on the build machine
  repoPath = "/mnt/zpool/code/nix-config";
  flakePath = "path://${repoPath}";
  notifications = config.my.monitoring.notifications;

  # Wake-on-LAN MAC addresses for physical hosts that might be powered off.
  # LXC containers are managed by incus and don't need WoL.
  wolMacs = {
    "taylor-desktop-nix" = "c8:7f:54:6c:e2:96";
    # "taylor-laptop-nix" = "aa:bb:cc:dd:ee:ff";
    # "pi-backup-nix" = "aa:bb:cc:dd:ee:ff";
  };

  wolCases = lib.concatStringsSep "\n      " (
    lib.mapAttrsToList (host: mac: ''${host}) echo "${mac}" ;;'') wolMacs
  );

  # Bash helpers shared across all deploy scripts.
  # notify "Title" <priority> "gotify body" ["extended email body"]
  sharedFns = ''
    GOTIFY_KEY=""
    if [ -r ${notifications.gotify.tokenFile} ]; then
      GOTIFY_KEY=$(${pkgs.coreutils}/bin/cat ${notifications.gotify.tokenFile} || true)
    fi

    notify() {
      local title="$1"
      local priority="$2"
      local body="$3"

      if [ -z "$GOTIFY_KEY" ]; then
        echo "Gotify token unavailable; skipping notification: $title"
        return 0
      fi

      ${pkgs.curl}/bin/curl -s -X POST "${notifications.gotify.url}" \
        -H "X-Gotify-Key: $GOTIFY_KEY" \
        -F "title=$title" \
        -F "message=$(printf '%b' "$body")" \
        -F "priority=$priority" > /dev/null || true
    }

    notify_email() {
      local title="$1"
      local priority="$2"
      local body="$3"
      local email_body="''${4:-$3}"

      notify "$title" "$priority" "$body"

      {
        printf 'To: ${notifications.recipientEmail}\n'
        printf 'Subject: %s\n' "$title"
        printf '\n'
        printf '%b\n' "$email_body"
      } | ${pkgs.msmtp}/bin/msmtp "${notifications.recipientEmail}" || true
    }

    deploy_log_email_body() {
      local log="$1"
      local heading="$2"
      local tail_lines="''${3:-120}"
      local failures
      failures=$(grep -E '^(error: Cannot build|error: builder for|error: cannot download|error: .*failed|Build failed:|Failed:|[[:space:]]*Reason:|[[:space:]]*For full logs, run:|[[:space:]]*nix log /nix/store/.*\.drv|curl: \([0-9]+\))' "$log" | tail -n 80 || true)

      {
        printf '%s\n\n' "$heading"
        if [ -n "$failures" ]; then
          printf 'Failure highlights:\n%s\n\n' "$failures"
        fi
        printf 'Last %s log lines:\n' "$tail_lines"
        tail -n "$tail_lines" "$log"
      }
    }

    list_colmena_hosts_for_tag() {
      local tag_name="$1"
      ${pkgs.nix}/bin/nix eval --json "${flakePath}#colmena" \
        --apply "hive: builtins.filter (n: n != \"meta\" && builtins.elem \"$tag_name\" ((builtins.getAttr n hive).deployment.tags or [])) (builtins.attrNames hive)" \
        | ${pkgs.jq}/bin/jq -r '.[]' | tr '\n' ' ' | xargs
    }

    deployed_system_path() {
      local host="$1"
      local self_hostname="$2"
      if [ "$host" = "$self_hostname" ]; then
        ${pkgs.coreutils}/bin/readlink -f /nix/var/nix/profiles/system
      else
        ${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" \
          "readlink -f /nix/var/nix/profiles/system"
      fi
    }

    deployed_system_generation() {
      local host="$1"
      local self_hostname="$2"
      if [ "$host" = "$self_hostname" ]; then
        ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --list-generations \
          | awk '$NF == "(current)" { print $1 }'
      else
        ${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" \
          "nix-env -p /nix/var/nix/profiles/system --list-generations | awk '\$NF == \"(current)\" { print \$1 }'"
      fi
    }

    sanitize_gcroot_label() {
      tr -c '[:alnum:]._+-' '-' | sed 's/^-*//; s/-*$//'
    }

    pin_deployed_system() {
      local host="$1"
      local self_hostname="$2"
      local profile
      local generation
      local root_label
      profile=$(deployed_system_path "$host" "$self_hostname" 2>/dev/null || true)
      if [ -z "$profile" ]; then
        echo "Unable to determine deployed system path for $host; skipping GC root."
        return 1
      fi
      if [ ! -e "$profile" ]; then
        echo "Deployed system path for $host is not present locally ($profile); skipping GC root."
        return 1
      fi
      generation=$(deployed_system_generation "$host" "$self_hostname" 2>/dev/null || true)
      root_label=$(printf 'gen%s-%s' "''${generation:-unknown}" "$(basename "$profile")" | sanitize_gcroot_label)
      pin_gc_roots "$host" "$profile" "$root_label"
    }

    get_wol_mac() {
      case "$1" in
        ${wolCases}
        *) echo "" ;;
      esac
    }

    try_wol() {
      local host="$1"
      local mac
      mac=$(get_wol_mac "$host")
      if [ -n "$mac" ]; then
        echo "Sending Wake-on-LAN to $host ($mac)..."
        ${pkgs.wol}/bin/wol "$mac" || true
        sleep 60
      fi
    }

    pin_gc_roots() {
      local hosts="$1"
      local store_paths="$2"
      local root_label="''${3:-}"
      local timestamp
      timestamp=$(date -u +%Y%m%d%H%M%S)
      local base=/nix/var/nix/gcroots/colmena-hosts
      mkdir -p "$base"
      for host in $hosts; do
        local hdir="$base/$host"
        mkdir -p "$hdir"
        # Only pin nixos-system-* closures, not every store path from logs
        for p in $store_paths; do
          [ -z "$p" ] && continue
          case "$(basename "$p")" in
            nixos-system-*) ;;
            *) continue ;;
          esac
          if [ -e "$p" ]; then
            local name
            if [ -n "$root_label" ]; then
              name="$timestamp-$root_label"
            else
              name="$timestamp-$(basename "$p")"
            fi
            ${pkgs.nix}/bin/nix-store --add-root "$hdir/$name" --indirect --realise "$p" || true
          fi
        done
        local keep=${toString keepRoots}
        ls -1 "$hdir" 2>/dev/null | sort -r | tail -n +$((keep+1)) | while read f; do
          rm -f "$hdir/$f" || true
        done || true
      done
      # Prune GC root dirs for hosts no longer in the Colmena hive
      local known
      known=$(${pkgs.nix}/bin/nix eval --json "${flakePath}#colmena" \
        --apply 'hive: builtins.filter (n: n != "meta") (builtins.attrNames hive)' \
        2>/dev/null | ${pkgs.jq}/bin/jq -r '.[]' || true)
      for d in "$base"/*; do
        [ -d "$d" ] || continue
        if [ -n "$known" ] && ! echo "$known" | grep -xq "$(basename "$d")"; then
          rm -rf "$d" || true
        fi
      done || true
    }
  '';

  servicePath = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.hostname
    pkgs.git
    pkgs.nix
    pkgs.colmena
    pkgs.openssh
    pkgs.jq
    pkgs.curl
    pkgs.msmtp
    pkgs.wol
  ];

  mkDeployService = name: tags: {
    description = "${name} Colmena Deploy";
    restartIfChanged = false;
    stopIfChanged = false;
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sops-nix.service"
    ];
    path = servicePath;
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail
      ${sharedFns}

      echo "--- Committing pre-deploy state ---"
      ${pkgs.git}/bin/git -C "${repoPath}" add -A
      ${pkgs.git}/bin/git -C "${repoPath}" commit -m "auto: ${name} pre-deploy $(date '+%Y-%m-%d %H:%M')" || true

      echo "--- Deploying ${name} (${tags}) ---"
      cd "${repoPath}"
      RETRY_DELAY=1800
      MAX_RETRIES=46
      BUILD_PARALLELISM=4

      # Enumerate all hosts for this tag
      TAG_NAME="${lib.removePrefix "@" tags}"
      ALL_HOSTS=$(list_colmena_hosts_for_tag "$TAG_NAME")

      if [ -z "$ALL_HOSTS" ]; then
        echo "No hosts found for tag '${tags}'"
        exit 0
      fi
      echo "Hosts to deploy: $ALL_HOSTS"

      echo "--- Building ${name} (${tags}) profiles locally ---"
      BUILD_LOG=$(mktemp)
      build_exit=0
      ${pkgs.colmena}/bin/colmena build --on '${tags}' --no-build-on-target --parallel "$BUILD_PARALLELISM" 2>&1 | tee "$BUILD_LOG" || build_exit=$?
      if [ $build_exit -ne 0 ]; then
        ERROR_SUMMARY=$(tail -n 20 "$BUILD_LOG")
        EMAIL_BODY=$(deploy_log_email_body "$BUILD_LOG" "Build log excerpt for ${name} (${tags}).")
        notify_email "❌ ${name}: build FAILED" 10 \
          "Last 20 lines:\n$ERROR_SUMMARY" \
          "$EMAIL_BODY"
        rm "$BUILD_LOG"
        exit $build_exit
      fi
      rm "$BUILD_LOG"

      SUCCEEDED_HOSTS=""
      HARD_FAIL_HOSTS=""
      CONN_FAIL_HOSTS=""
      HAD_WARNINGS=false

      SELF_HOSTNAME=$(hostname)

      # --- First pass: deploy each already-built host individually so one offline host can't abort others ---
      for host in $ALL_HOSTS; do
        echo "--- [$host] deploying ---"
        LOG=$(mktemp)
        colmena_exit=0
        if [ "$host" = "$SELF_HOSTNAME" ]; then
          ${pkgs.colmena}/bin/colmena apply-local switch 2>&1 | tee "$LOG" || colmena_exit=$?
        else
          ${pkgs.colmena}/bin/colmena apply --on "$host" --no-build-on-target --no-substitute switch 2>&1 | tee "$LOG" || colmena_exit=$?
        fi

        grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

        if [ $colmena_exit -eq 0 ]; then
          SUCCEEDED_HOSTS="$SUCCEEDED_HOSTS $host"
          pin_deployed_system "$host" "$SELF_HOSTNAME" || true
        else
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          if grep -qE 'ssh: connect|Connection refused|No route to host|Connection timed out|Network is unreachable|Could not connect|ssh_exchange_identification' "$LOG"; then
            CONN_FAIL_HOSTS="$CONN_FAIL_HOSTS $host"
          else
            HARD_FAIL_HOSTS="$HARD_FAIL_HOSTS $host"
            EMAIL_BODY=$(deploy_log_email_body "$LOG" "Build log excerpt for $host (${name}).")
            notify_email "❌ ${name}: $host FAILED" 10 \
              "Last 20 lines:\n$ERROR_SUMMARY" \
              "$EMAIL_BODY"
          fi
        fi
        rm "$LOG"
      done

      SUCCEEDED_HOSTS=$(echo "$SUCCEEDED_HOSTS" | xargs || true)
      HARD_FAIL_HOSTS=$(echo "$HARD_FAIL_HOSTS" | xargs || true)
      CONN_FAIL_HOSTS=$(echo "$CONN_FAIL_HOSTS" | xargs || true)

      # --- First-pass summary ---
      SUCC_DISP=$SUCCEEDED_HOSTS;  [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
      HARD_DISP=$HARD_FAIL_HOSTS;  [ -n "$HARD_DISP" ] || HARD_DISP="none"
      CONN_DISP=$CONN_FAIL_HOSTS;  [ -n "$CONN_DISP" ] || CONN_DISP="none"
      notify "ℹ️ ${name} first-pass summary" 3 \
        "Succeeded: $SUCC_DISP\nHard failed: $HARD_DISP\nRetrying (conn): $CONN_DISP"

      # --- WoL + retry connection-failed hosts ---
      for host in $CONN_FAIL_HOSTS; do
        try_wol "$host"
        host_ok=false
        for attempt in $(seq 1 $MAX_RETRIES); do
          echo "[$host] retry $attempt/$MAX_RETRIES, sleeping $((RETRY_DELAY / 60)) min..."
          sleep $RETRY_DELAY
          LOG=$(mktemp)
          colmena_exit=0
          if [ "$host" = "$SELF_HOSTNAME" ]; then
            ${pkgs.colmena}/bin/colmena apply-local switch 2>&1 | tee "$LOG" || colmena_exit=$?
          else
            ${pkgs.colmena}/bin/colmena apply --on "$host" --no-build-on-target --no-substitute switch 2>&1 | tee "$LOG" || colmena_exit=$?
          fi

          grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true
          rm "$LOG"

          if [ $colmena_exit -eq 0 ]; then
            SUCCEEDED_HOSTS="$SUCCEEDED_HOSTS $host"
            pin_deployed_system "$host" "$SELF_HOSTNAME" || true
            host_ok=true
            break
          fi

          # Re-send WoL every 5 retries in case machine went back to sleep
          if [ $((attempt % 5)) -eq 0 ]; then
            try_wol "$host"
          fi
        done

        if [ "$host_ok" = false ]; then
          HARD_FAIL_HOSTS="$HARD_FAIL_HOSTS $host"
          notify_email "❌ ${name}: $host FAILED (retries exhausted)" 10 \
            "All $MAX_RETRIES connection retries exhausted for $host"
        fi
      done

      SUCCEEDED_HOSTS=$(echo "$SUCCEEDED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
      HARD_FAIL_HOSTS=$(echo "$HARD_FAIL_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)

      # --- Final summary ---
      SUCC_DISP=$SUCCEEDED_HOSTS; [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
      FAIL_DISP=$HARD_FAIL_HOSTS; [ -n "$FAIL_DISP" ] || FAIL_DISP="none"
      if [ -n "$HARD_FAIL_HOSTS" ]; then
        notify "⚠️ ${name} deploy partial" 6 \
          "Succeeded: $SUCC_DISP\nFailed: $FAIL_DISP"
      elif [ "$HAD_WARNINGS" = true ]; then
        notify "⚠️ ${name} deploy succeeded (with warnings)" 4 \
          "All hosts: $SUCC_DISP"
      else
        notify "✅ ${name} deploy succeeded" 3 \
          "All hosts: $SUCC_DISP"
      fi

      # --- Version commit for succeeded hosts ---
      if [ -n "$SUCCEEDED_HOSTS" ]; then
        REVISIONS=""
        for host in $SUCCEEDED_HOSTS; do
          if [ "$host" = "$SELF_HOSTNAME" ]; then
            VER=$(nixos-version 2>/dev/null || echo "unknown")
          else
            VER=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" nixos-version 2>/dev/null || echo "unreachable")
          fi
          REVISIONS+="$host: $VER\n"
        done
        COMMIT_MSG=$(printf 'auto: ${name} deploy %s\n\n%b' "$(date '+%Y-%m-%d %H:%M')" "$REVISIONS")
        ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
        ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true
      fi

      [ -z "$HARD_FAIL_HOSTS" ] || exit 1
    '';
  };

  deployCmd = pkgs.writeShellScriptBin "deploy" ''
    set -euo pipefail
    ${sharedFns}

    if [ $# -lt 1 ]; then
      echo "Usage: deploy <host|@tag> [goal]"
      echo "  Examples:"
      echo "    deploy laptop-nix"
      echo "    deploy desktop-nix boot"
      echo "    deploy @weekly"
      echo "    deploy build-nix        (uses apply-local)"
      exit 1
    fi

    TARGET="$1"
    GOAL="''${2:-switch}"
    HOSTNAME=$(hostname)
    BUILD_PARALLELISM=4

    cd "${repoPath}"

    echo "--- Committing pre-deploy state ---"
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git commit -m "auto: manual deploy $TARGET $(date '+%Y-%m-%d %H:%M')" || true

    if [[ "$TARGET" == @* ]]; then
      SELECTED_HOSTS=$(list_colmena_hosts_for_tag "''${TARGET#@}")
    else
      SELECTED_HOSTS="$TARGET"
    fi

    echo "--- Building $TARGET profiles locally ---"
    BUILD_LOG=$(mktemp)
    BUILD_EXIT=0
    ${pkgs.colmena}/bin/colmena build --on "$TARGET" --no-build-on-target --parallel "$BUILD_PARALLELISM" 2>&1 | tee "$BUILD_LOG" || BUILD_EXIT=$?
    if [ $BUILD_EXIT -ne 0 ]; then
      ERROR_SUMMARY=$(tail -n 20 "$BUILD_LOG")
      EMAIL_BODY=$(deploy_log_email_body "$BUILD_LOG" "Build log excerpt for manual deploy $TARGET (goal=$GOAL).")
      notify_email "❌ Manual deploy $TARGET build FAILED" 10 \
        "Last 20 lines:\n$ERROR_SUMMARY" \
        "$EMAIL_BODY"
      rm "$BUILD_LOG"
      exit $BUILD_EXIT
    fi
    rm "$BUILD_LOG"

    SUCCEEDED_HOSTS=""
    FAILED_HOSTS=""
    HAD_WARNINGS=false

    if [[ "$TARGET" == @* ]]; then
      for host in $SELECTED_HOSTS; do
        LOG=$(mktemp)
        host_exit=0
        echo "--- Deploying $host ($GOAL) ---"
        if [[ "$host" == "$HOSTNAME" ]] || [[ "$host" == "build-nix" && "$HOSTNAME" == "build-nix" ]]; then
          ${pkgs.colmena}/bin/colmena apply-local "$GOAL" 2>&1 | tee "$LOG" || host_exit=$?
        else
          ${pkgs.colmena}/bin/colmena apply --on "$host" --parallel 1 --no-build-on-target "$GOAL" 2>&1 | tee "$LOG" || host_exit=$?
        fi

        grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

        if [ $host_exit -eq 0 ]; then
          SUCCEEDED_HOSTS="$SUCCEEDED_HOSTS $host"
          pin_deployed_system "$host" "$HOSTNAME" || true
        else
          FAILED_HOSTS="$FAILED_HOSTS $host"
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          EMAIL_BODY=$(deploy_log_email_body "$LOG" "Build log excerpt for manual deploy $host (goal=$GOAL).")
          notify_email "❌ Manual deploy $host FAILED" 10 \
            "Last 20 lines:\n$ERROR_SUMMARY" \
            "$EMAIL_BODY"
        fi
        rm "$LOG"
      done
    else
      LOG=$(mktemp)
      host_exit=0

      if [[ "$TARGET" == "$HOSTNAME" ]] || [[ "$TARGET" == "build-nix" && "$HOSTNAME" == "build-nix" ]]; then
        echo "--- Local deploy (apply-local $GOAL) ---"
        ${pkgs.colmena}/bin/colmena apply-local "$GOAL" 2>&1 | tee "$LOG" || host_exit=$?
      else
        echo "--- Deploying $TARGET ($GOAL) ---"
        ${pkgs.colmena}/bin/colmena apply --on "$TARGET" --parallel 4 --no-build-on-target "$GOAL" 2>&1 | tee "$LOG" || host_exit=$?
      fi

      grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

      if [ $host_exit -eq 0 ]; then
        SUCCEEDED_HOSTS="$TARGET"
        pin_deployed_system "$TARGET" "$HOSTNAME" || true
      else
        FAILED_HOSTS="$TARGET"
        ERROR_SUMMARY=$(tail -n 20 "$LOG")
        EMAIL_BODY=$(deploy_log_email_body "$LOG" "Build log excerpt for manual deploy $TARGET (goal=$GOAL).")
        notify_email "❌ Manual deploy $TARGET FAILED" 10 \
          "Last 20 lines:\n$ERROR_SUMMARY" \
          "$EMAIL_BODY"
      fi
      rm "$LOG"
    fi

    SUCCEEDED_HOSTS=$(echo "$SUCCEEDED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
    FAILED_HOSTS=$(echo "$FAILED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
    SUCC_DISP=$SUCCEEDED_HOSTS; [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
    FAIL_DISP=$FAILED_HOSTS; [ -n "$FAIL_DISP" ] || FAIL_DISP="none"

    if [ -z "$FAILED_HOSTS" ]; then
      if [ "$HAD_WARNINGS" = true ]; then
        notify "⚠️ Manual deploy $TARGET succeeded (with warnings)" 4 \
          "Succeeded: $SUCC_DISP\nGoal: $GOAL"
      else
        notify "✅ Manual deploy $TARGET succeeded" 3 \
          "Succeeded: $SUCC_DISP\nGoal: $GOAL"
      fi
      ${pkgs.git}/bin/git add flake.lock
      ${pkgs.git}/bin/git commit -m "auto: manual deploy $TARGET $(date '+%Y-%m-%d %H:%M')" || true
    else
      notify "⚠️ Manual deploy $TARGET partial" 6 \
        "Succeeded: $SUCC_DISP\nFailed: $FAIL_DISP\nGoal: $GOAL"
    fi

    [ -z "$FAILED_HOSTS" ] || exit 1
  '';

  deployOldCmd = pkgs.writeShellScriptBin "deploy-old" ''
    set -euo pipefail
    ${sharedFns}

    if [ $# -lt 2 ]; then
      echo "Usage: deploy-old <host> <-N>  (e.g. deploy-old taylor-laptop-nix -2)"
      exit 1
    fi

    HOST="$1"
    OFFSET_RAW="$2"
    if [[ "$OFFSET_RAW" != -* ]]; then
      echo "Second arg must be a negative offset like -2"
      exit 1
    fi
    OFFSET="''${OFFSET_RAW#-}"

    GCROOT_DIR="/nix/var/nix/gcroots/colmena-hosts/$HOST"
    if [ -d "$GCROOT_DIR" ]; then
      # copy available closures from build host to target to reduce rebuilds
      echo "Copying available closures to $HOST..."
      for lnk in "$GCROOT_DIR"/*; do
        [ -L "$lnk" ] || continue
        PATH_TO_COPY=$(readlink -f "$lnk")
        if [ -e "$PATH_TO_COPY" ]; then
          ${pkgs.nix}/bin/nix copy --to ssh://root@$HOST "$PATH_TO_COPY" || true
        fi
      done
    fi

    # determine target generation on remote
    GEN=$(${pkgs.openssh}/bin/ssh -o BatchMode=yes root@"$HOST" "nix-env -p /nix/var/nix/profiles/system --list-generations | tail -n \"$OFFSET\" | head -n 1 | awk '{print \$1}'" || echo "")
    if [ -z "$GEN" ]; then
      echo "Unable to determine target generation on $HOST"
      exit 1
    fi

    echo "Switching $HOST to generation $GEN"
    if ${pkgs.openssh}/bin/ssh -o BatchMode=yes root@"$HOST" "sudo nix-env -p /nix/var/nix/profiles/system --switch-generation $GEN && sudo /nix/var/nix/profiles/system/activate"; then
      notify "🔄 Rollback: $HOST → gen $GEN" 5 \
        "$HOST switched to generation $GEN"
      echo "deploy-old completed for $HOST -> generation $GEN"
    else
      notify_email "❌ Rollback FAILED: $HOST → gen $GEN" 10 \
        "Remote activation failed on $HOST for generation $GEN.\nIf the activation failed due to missing store paths, run 'nix copy' from a machine that has the closures."
      echo "Remote activation failed on $HOST. If the activation failed due to missing store paths, run 'nix copy' from a machine that has the closures."
      exit 1
    fi
  '';

  mkTimer = name: onCalendar: {
    enable = true;
    description = "Run ${name} Colmena Deploy";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = onCalendar;
      Persistent = true;
      Unit = "deploy-${name}.service";
    };
  };

in
{
  environment.systemPackages = [
    deployCmd
    deployOldCmd
  ];

  systemd.services = {
    "flake-update" = {
      description = "Update nix flake inputs";
      restartIfChanged = false;
      stopIfChanged = false;
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.git
        pkgs.nix
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -euo pipefail
        echo "--- Updating flake ---"
        cd "${repoPath}"
        ${pkgs.nix}/bin/nix flake update --flake "${flakePath}"
        ${pkgs.git}/bin/git add flake.lock
        ${pkgs.git}/bin/git commit -m "auto: flake update $(date '+%Y-%m-%d %H:%M')" || true
      '';
    };
    "deploy-Daily" = mkDeployService "Daily" "@daily";
    "deploy-Weekly" = mkDeployService "Weekly" "@weekly";
    "deploy-Monthly" = mkDeployService "Monthly" "@monthly";
  };

  systemd.timers = {
    "flake-update" = {
      enable = true;
      description = "Update nix flake inputs every 6 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/6:00:00";
        Persistent = true;
        Unit = "flake-update.service";
      };
    };
    "deploy-Daily" = mkTimer "Daily" "*-*-* 00:00";
    "deploy-Weekly" = mkTimer "Weekly" "Sat *-*-* 01:00";
    "deploy-Monthly" = mkTimer "Monthly" "Sat *-*-1..7 02:00";
  };
}
