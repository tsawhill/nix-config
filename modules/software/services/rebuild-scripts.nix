{
  config,
  pkgs,
  lib,
  networkTopology,
  ...
}:

let
  keepRoots = 5; # number of per-host deploy GC roots to retain on the build machine
  repoPath = "/mnt/zpool/code/nix-config";
  flakePath = "path://${repoPath}";
  retryStateDir = "/var/lib/colmena-deploy-retries";
  deployLockPath = "/run/lock/colmena-deploy.lock";
  perHostBuildTimeout = "6h";
  applyTimeout = "90m";
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
    RETRY_STATE_DIR="${retryStateDir}"
    DEPLOY_LOCK_PATH="${deployLockPath}"
    PER_HOST_BUILD_TIMEOUT="${perHostBuildTimeout}"
    APPLY_TIMEOUT="${applyTimeout}"

    log_phase() {
      printf '[%s] --- %s ---\n' "$(date -Is)" "$*"
    }

    acquire_deploy_lock() {
      local owner="$1"
      exec 9>"$DEPLOY_LOCK_PATH"
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        log_phase "Another deploy is already running; skipping $owner"
        return 1
      fi
    }

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

    is_retryable_deploy_failure() {
      local log="$1"
      local exit_code="''${2:-1}"

      if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
        return 0
      fi

      grep -qE '(ssh: connect|Connection refused|No route to host|Connection timed out|Network is unreachable|Could not connect|Could not resolve hostname|ssh_exchange_identification|kex_exchange_identification|Connection reset|Connection closed|Broken pipe|Host is down|Operation timed out|failed to connect|cannot connect)' "$log"
    }

    sanitize_state_label() {
      tr -c '[:alnum:]._+-' '-' | sed 's/^-*//; s/-*$//'
    }

    retry_record_path() {
      local schedule="$1"
      local host="$2"
      local schedule_label
      local host_label
      schedule_label=$(printf '%s' "$schedule" | sanitize_state_label)
      host_label=$(printf '%s' "$host" | sanitize_state_label)
      printf '%s/%s/%s.env\n' "$RETRY_STATE_DIR" "$schedule_label" "$host_label"
    }

    write_retry_record() {
      local schedule="$1"
      local tag="$2"
      local host="$3"
      local system_path="$4"
      local goal="$5"
      local build_id="$6"
      local record
      local dir
      local tmp

      [ -n "$host" ] || return 1
      [ -n "$system_path" ] || return 1
      record=$(retry_record_path "$schedule" "$host")
      dir=$(dirname "$record")
      mkdir -p "$dir"
      tmp="$record.tmp.$$"
      {
        printf 'schedule=%q\n' "$schedule"
        printf 'tag=%q\n' "$tag"
        printf 'host=%q\n' "$host"
        printf 'system_path=%q\n' "$system_path"
        printf 'goal=%q\n' "$goal"
        printf 'build_id=%q\n' "$build_id"
        printf 'created_at=%q\n' "$(date -Is)"
      } > "$tmp"
      chmod 0600 "$tmp"
      mv "$tmp" "$record"
    }

    delete_retry_record() {
      local schedule="$1"
      local host="$2"
      local record
      record=$(retry_record_path "$schedule" "$host")
      rm -f "$record"
    }

    clear_retry_schedule() {
      local schedule="$1"
      local schedule_label
      local dir
      schedule_label=$(printf '%s' "$schedule" | sanitize_state_label)
      dir="$RETRY_STATE_DIR/$schedule_label"
      if [ -d "$dir" ]; then
        log_phase "Clearing queued retries for $schedule"
        find "$dir" -type f -name '*.env' -delete
      fi
    }

    clear_retry_host() {
      local host="$1"
      local host_label
      local record
      host_label=$(printf '%s' "$host" | sanitize_state_label)
      for record in "$RETRY_STATE_DIR"/*/"$host_label.env"; do
        [ -e "$record" ] || continue
        log_phase "Clearing queued retry for $host"
        rm -f "$record"
      done
    }

    list_colmena_hosts_for_tag() {
      local tag_name="$1"
      ${pkgs.nix}/bin/nix eval --json "${flakePath}#colmena" \
        --apply "hive: builtins.filter (n: n != \"meta\" && builtins.elem \"$tag_name\" ((builtins.getAttr n hive).deployment.tags or [])) (builtins.attrNames hive)" \
        | ${pkgs.jq}/bin/jq -r '.[]' | tr '\n' ' ' | xargs
    }

    list_colmena_hosts() {
      ${pkgs.nix}/bin/nix eval --json "${flakePath}#colmena" \
        --apply 'hive: builtins.filter (n: n != "meta") (builtins.attrNames hive)' \
        | ${pkgs.jq}/bin/jq -r '.[]' | tr '\n' ' ' | xargs
    }

    expand_colmena_selector() {
      local selector="$1"
      local item
      local hosts
      local host
      local expanded=""
      local -a selectors
      IFS=',' read -ra selectors <<< "$selector"
      for item in "''${selectors[@]}"; do
        [ -n "$item" ] || continue
        if [[ "$item" == @* ]]; then
          hosts=$(list_colmena_hosts_for_tag "''${item#@}")
          expanded=$(printf '%s\n%s\n' "$expanded" "$hosts")
        else
          hosts=$(list_colmena_hosts)
          for host in $hosts; do
            if [[ "$host" == $item ]]; then
              expanded=$(printf '%s\n%s\n' "$expanded" "$host")
            fi
          done
        fi
      done
      printf '%s\n' "$expanded" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs
    }

    local_build_system_path() {
      local host="$1"
      local log="$2"
      local build_exit
      local profile
      build_exit=0
      log_phase "$host: per-host build started (timeout $PER_HOST_BUILD_TIMEOUT)" >&2
      ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$PER_HOST_BUILD_TIMEOUT" \
        ${pkgs.colmena}/bin/colmena build --on "$host" --no-build-on-target --parallel 1 \
        2>&1 | tee "$log" >&2 || build_exit=$?
      if [ $build_exit -eq 0 ]; then
        profile=$(grep -oE '/nix/store/[a-z0-9]+-nixos-system-[^[:space:]]+' "$log" | tail -n 1 || true)
        if [ -z "$profile" ]; then
          profile=$(grep -oE '/nix/store/[a-z0-9]+[^[:space:]]*' "$log" | grep '/nixos-system-' | tail -n 1 || true)
        fi
      fi
      if [ $build_exit -ne 0 ]; then
        return $build_exit
      fi
      [ -n "$profile" ] || return 1
      log_phase "$host: per-host build completed ($profile)" >&2
      printf '%s\n' "$profile"
    }

    ssh_host_for_colmena_host() {
      local host="$1"
      case "$host" in
        *.*) printf '%s\n' "$host" ;;
        *) printf '%s.${networkTopology.domains.lan}\n' "$host" ;;
      esac
    }

    sanitize_gcroot_label() {
      tr -c '[:alnum:]._+-' '-' | sed 's/^-*//; s/-*$//'
    }

    pin_built_system() {
      local host="$1"
      local store_path="$2"
      local root_label
      [ -n "$store_path" ] || return 1
      [ -e "$store_path" ] || return 1
      root_label=$(printf 'built-%s' "$(basename "$store_path")" | sanitize_gcroot_label)
      echo "Pinning built system for $host: $store_path"
      pin_gc_roots "$host" "$store_path" "$root_label"
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
    pkgs.util-linux
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

      if ! acquire_deploy_lock "${name} deploy"; then
        exit 0
      fi

      log_phase "${name}: committing pre-deploy state"
      ${pkgs.git}/bin/git -C "${repoPath}" add -A
      ${pkgs.git}/bin/git -C "${repoPath}" commit -m "auto: ${name} pre-deploy $(date '+%Y-%m-%d %H:%M')" || true

      log_phase "Deploying ${name} (${tags})"
      cd "${repoPath}"
      BUILD_ID=$(date -u +%Y%m%d%H%M%S)

      # Enumerate all hosts for this tag
      log_phase "${name}: resolving hosts for ${tags}"
      TAG_NAME="${lib.removePrefix "@" tags}"
      ALL_HOSTS=$(list_colmena_hosts_for_tag "$TAG_NAME")

      if [ -z "$ALL_HOSTS" ]; then
        log_phase "No hosts found for tag '${tags}'"
        exit 0
      fi
      log_phase "${name}: hosts to deploy: $ALL_HOSTS"
      clear_retry_schedule "${name}"

      HAD_WARNINGS=false

      SUCCEEDED_HOSTS=""
      HARD_FAIL_HOSTS=""
      DEFERRED_HOSTS=""

      SELF_HOSTNAME=$(hostname)

      # --- First pass: deploy each already-built host individually so one offline host can't abort others ---
      for host in $ALL_HOSTS; do
        log_phase "$host: scheduled build phase"
        LOG=$(mktemp)
        build_exit=0
        colmena_exit=0
        system_path=$(local_build_system_path "$host" "$LOG") || build_exit=$?
        if [ $build_exit -eq 0 ]; then
          log_phase "$host: pinning built system"
          pin_built_system "$host" "$system_path" || true
        else
          HARD_FAIL_HOSTS="$HARD_FAIL_HOSTS $host"
          EMAIL_BODY=$(deploy_log_email_body "$LOG" "Build log excerpt for $host (${name}).")
          notify_email "❌ ${name}: $host build FAILED" 10 \
            "Per-host build failed for $host." \
            "$EMAIL_BODY"
          rm "$LOG"
          continue
        fi

        log_phase "$host: queueing retry record for $system_path"
        write_retry_record "${name}" '${tags}' "$host" "$system_path" "switch" "$BUILD_ID"

        log_phase "$host: first apply started (timeout $APPLY_TIMEOUT)"
        if [ "$host" = "$SELF_HOSTNAME" ]; then
          ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
            ${pkgs.colmena}/bin/colmena apply-local switch 2>&1 | tee "$LOG" || colmena_exit=$?
        else
          ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
            ${pkgs.colmena}/bin/colmena apply --on "$host" --no-build-on-target --no-substitute switch \
            2>&1 | tee "$LOG" || colmena_exit=$?
        fi

        grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

        if [ $colmena_exit -eq 0 ]; then
          log_phase "$host: first apply completed"
          SUCCEEDED_HOSTS="$SUCCEEDED_HOSTS $host"
          delete_retry_record "${name}" "$host"
        else
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          if is_retryable_deploy_failure "$LOG" "$colmena_exit"; then
            DEFERRED_HOSTS="$DEFERRED_HOSTS $host"
            notify "⚠️ ${name}: $host deferred" 5 \
              "First apply failed or timed out; retrying every 30 minutes until the next ${name} build.\nSystem: $system_path\nLast 20 lines:\n$ERROR_SUMMARY"
          else
            HARD_FAIL_HOSTS="$HARD_FAIL_HOSTS $host"
            delete_retry_record "${name}" "$host"
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
      DEFERRED_HOSTS=$(echo "$DEFERRED_HOSTS" | xargs || true)

      # --- First-pass summary ---
      SUCC_DISP=$SUCCEEDED_HOSTS;  [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
      HARD_DISP=$HARD_FAIL_HOSTS;  [ -n "$HARD_DISP" ] || HARD_DISP="none"
      DEFER_DISP=$DEFERRED_HOSTS;  [ -n "$DEFER_DISP" ] || DEFER_DISP="none"
      notify "ℹ️ ${name} first-pass summary" 3 \
        "Succeeded: $SUCC_DISP\nHard failed: $HARD_DISP\nDeferred: $DEFER_DISP"

      SUCCEEDED_HOSTS=$(echo "$SUCCEEDED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
      HARD_FAIL_HOSTS=$(echo "$HARD_FAIL_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
      DEFERRED_HOSTS=$(echo "$DEFERRED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)

      # --- Final summary ---
      SUCC_DISP=$SUCCEEDED_HOSTS; [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
      FAIL_DISP=$HARD_FAIL_HOSTS; [ -n "$FAIL_DISP" ] || FAIL_DISP="none"
      DEFER_DISP=$DEFERRED_HOSTS; [ -n "$DEFER_DISP" ] || DEFER_DISP="none"
      log_phase "${name}: final summary; succeeded=$SUCC_DISP hard_failed=$FAIL_DISP deferred=$DEFER_DISP"
      if [ -n "$HARD_FAIL_HOSTS" ]; then
        notify "⚠️ ${name} deploy partial" 6 \
          "Succeeded: $SUCC_DISP\nFailed: $FAIL_DISP\nDeferred: $DEFER_DISP"
      elif [ -n "$DEFERRED_HOSTS" ]; then
        notify "⚠️ ${name} deploy deferred" 5 \
          "Succeeded: $SUCC_DISP\nDeferred: $DEFER_DISP"
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
            ssh_host=$(ssh_host_for_colmena_host "$host")
            VER=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$ssh_host" nixos-version 2>/dev/null || echo "unreachable")
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

    if ! acquire_deploy_lock "manual deploy"; then
      exit 1
    fi

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

    cd "${repoPath}"

    log_phase "Manual deploy $TARGET: committing pre-deploy state"
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git commit -m "auto: manual deploy $TARGET $(date '+%Y-%m-%d %H:%M')" || true

    log_phase "Manual deploy $TARGET: resolving hosts"
    SELECTED_HOSTS=$(expand_colmena_selector "$TARGET")
    if [ -z "$SELECTED_HOSTS" ]; then
      echo "No hosts matched selector '$TARGET'"
      exit 1
    fi
    log_phase "Manual deploy $TARGET: hosts to deploy: $SELECTED_HOSTS"

    HAD_WARNINGS=false

    SUCCEEDED_HOSTS=""
    FAILED_HOSTS=""

    for host in $SELECTED_HOSTS; do
      LOG=$(mktemp)
      build_exit=0
      host_exit=0
      log_phase "$host: manual build phase ($GOAL)"
      system_path=$(local_build_system_path "$host" "$LOG") || build_exit=$?
      if [ $build_exit -eq 0 ]; then
        log_phase "$host: pinning built system"
        pin_built_system "$host" "$system_path" || true
      else
        FAILED_HOSTS="$FAILED_HOSTS $host"
        EMAIL_BODY=$(deploy_log_email_body "$LOG" "Build log excerpt for manual deploy $host (goal=$GOAL).")
        notify_email "❌ Manual deploy $host build FAILED" 10 \
          "Per-host build failed for $host." \
          "$EMAIL_BODY"
        rm "$LOG"
        continue
      fi

      log_phase "$host: manual apply started ($GOAL, timeout $APPLY_TIMEOUT)"
      if [[ "$host" == "$HOSTNAME" ]] || [[ "$host" == "build-nix" && "$HOSTNAME" == "build-nix" ]]; then
        ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
          ${pkgs.colmena}/bin/colmena apply-local "$GOAL" 2>&1 | tee "$LOG" || host_exit=$?
      else
        ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
          ${pkgs.colmena}/bin/colmena apply --on "$host" --parallel 1 --no-build-on-target "$GOAL" \
          2>&1 | tee "$LOG" || host_exit=$?
      fi

      grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

      if [ $host_exit -eq 0 ]; then
        log_phase "$host: manual apply completed"
        SUCCEEDED_HOSTS="$SUCCEEDED_HOSTS $host"
        clear_retry_host "$host"
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

    SUCCEEDED_HOSTS=$(echo "$SUCCEEDED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
    FAILED_HOSTS=$(echo "$FAILED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
    SUCC_DISP=$SUCCEEDED_HOSTS; [ -n "$SUCC_DISP" ] || SUCC_DISP="none"
    FAIL_DISP=$FAILED_HOSTS; [ -n "$FAIL_DISP" ] || FAIL_DISP="none"
    log_phase "Manual deploy $TARGET: final summary; succeeded=$SUCC_DISP failed=$FAIL_DISP goal=$GOAL"

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
    SSH_HOST=$(ssh_host_for_colmena_host "$HOST")
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
          ${pkgs.nix}/bin/nix copy --to ssh://root@$SSH_HOST "$PATH_TO_COPY" || true
        fi
      done
    fi

    # determine target generation on remote
    GEN=$(${pkgs.openssh}/bin/ssh -o BatchMode=yes root@"$SSH_HOST" "nix-env -p /nix/var/nix/profiles/system --list-generations | tail -n \"$OFFSET\" | head -n 1 | awk '{print \$1}'" || echo "")
    if [ -z "$GEN" ]; then
      echo "Unable to determine target generation on $HOST"
      exit 1
    fi

    echo "Switching $HOST to generation $GEN"
    if ${pkgs.openssh}/bin/ssh -o BatchMode=yes root@"$SSH_HOST" "sudo nix-env -p /nix/var/nix/profiles/system --switch-generation $GEN && sudo /nix/var/nix/profiles/system/activate"; then
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

  deployRetryCmd = pkgs.writeShellScriptBin "deploy-retry" ''
    set -euo pipefail
    ${sharedFns}

    if ! acquire_deploy_lock "deploy retry"; then
      exit 0
    fi

    cd "${repoPath}"
    mkdir -p "$RETRY_STATE_DIR"
    shopt -s nullglob

    log_phase "Deploy retry: scanning $RETRY_STATE_DIR"

    for record in "$RETRY_STATE_DIR"/*/*.env; do
      [ -e "$record" ] || continue

      unset schedule tag host system_path goal build_id created_at
      # shellcheck disable=SC1090
      source "$record"

      schedule="''${schedule:-}"
      tag="''${tag:-}"
      host="''${host:-}"
      system_path="''${system_path:-}"
      goal="''${goal:-switch}"
      build_id="''${build_id:-unknown}"

      if [ -z "$schedule" ] || [ -z "$host" ] || [ -z "$system_path" ]; then
        log_phase "Deploy retry: removing invalid retry record $record"
        rm -f "$record"
        continue
      fi

      if [ ! -e "$system_path" ]; then
        log_phase "Deploy retry: $host queued system path is missing: $system_path"
        notify_email "❌ Deploy retry $host stale" 10 \
          "Queued retry for $host cannot continue because the local system path no longer exists:\n$system_path"
        rm -f "$record"
        continue
      fi

      LOG=$(mktemp)
      retry_exit=0
      SELF_HOSTNAME=$(hostname)
      log_phase "Deploy retry: $host from $schedule build $build_id started (timeout $APPLY_TIMEOUT)"
      try_wol "$host"

      if [[ "$host" == "$SELF_HOSTNAME" ]] || [[ "$host" == "build-nix" && "$SELF_HOSTNAME" == "build-nix" ]]; then
        ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
          ${pkgs.bash}/bin/bash -c '
            set -euo pipefail
            system_path="$1"
            goal="$2"
            ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$system_path"
            "$system_path/bin/switch-to-configuration" "$goal"
          ' bash "$system_path" "$goal" 2>&1 | tee "$LOG" || retry_exit=$?
      else
        ssh_host=$(ssh_host_for_colmena_host "$host")
        ${pkgs.coreutils}/bin/timeout --foreground --kill-after=60s "$APPLY_TIMEOUT" \
          ${pkgs.bash}/bin/bash -c '
            set -euo pipefail
            ssh_host="$1"
            system_path="$2"
            goal="$3"
            export NIX_SSHOPTS="-o ConnectTimeout=15 -o BatchMode=yes"
            ${pkgs.nix}/bin/nix copy --to "ssh://root@$ssh_host" "$system_path"
            ${pkgs.openssh}/bin/ssh -o ConnectTimeout=15 -o BatchMode=yes "root@$ssh_host" \
              "nix-env -p /nix/var/nix/profiles/system --set $system_path && $system_path/bin/switch-to-configuration $goal"
          ' bash "$ssh_host" "$system_path" "$goal" 2>&1 | tee "$LOG" || retry_exit=$?
      fi

      if [ $retry_exit -eq 0 ]; then
        log_phase "Deploy retry: $host succeeded"
        rm -f "$record"
        notify "✅ Deploy retry $host succeeded" 3 \
          "$host applied queued $schedule build $build_id.\nSystem: $system_path"
      elif is_retryable_deploy_failure "$LOG" "$retry_exit"; then
        log_phase "Deploy retry: $host still unreachable or timed out; keeping queued retry"
      else
        ERROR_SUMMARY=$(tail -n 20 "$LOG")
        EMAIL_BODY=$(deploy_log_email_body "$LOG" "Retry log excerpt for $host ($schedule build $build_id).")
        log_phase "Deploy retry: $host failed hard; removing queued retry"
        notify_email "❌ Deploy retry $host FAILED" 10 \
          "Queued retry failed with a non-connection error and has been removed.\nLast 20 lines:\n$ERROR_SUMMARY" \
          "$EMAIL_BODY"
        rm -f "$record"
      fi

      rm "$LOG"
    done
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
    deployRetryCmd
  ];

  systemd.tmpfiles.rules = [
    "d ${retryStateDir} 0700 root root -"
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
    "deploy-retry" = {
      description = "Retry deferred Colmena deploys";
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
        ${deployRetryCmd}/bin/deploy-retry
      '';
    };
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
    "deploy-retry" = {
      enable = true;
      description = "Retry deferred Colmena deploys every 30 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:0/30:00";
        Persistent = true;
        Unit = "deploy-retry.service";
      };
    };
  };
}
