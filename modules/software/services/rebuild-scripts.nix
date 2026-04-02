{ pkgs, ... }:

let
  keepRoots = 14; # number of per-host deploy GC roots to retain on the build machine
  repoPath = "/mnt/zpool/code/nix-config";
  flakePath = "path://${repoPath}";

  mkDeployService = name: tags: {
    description = "${name} Colmena Deploy";
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail

      echo "--- Updating flake ---"
      ${pkgs.nix}/bin/nix flake update --flake "${flakePath}"

      echo "--- Committing pre-deploy state ---"
      ${pkgs.git}/bin/git -C "${repoPath}" add -A
      ${pkgs.git}/bin/git -C "${repoPath}" commit -m "auto: ${name} pre-deploy $(date '+%Y-%m-%d %H:%M')" || true

      echo "--- Deploying ${name} (${tags}) ---"
      cd "${repoPath}"
      RETRY_DELAY=1800
      MAX_RETRIES=46
      PENDING='${tags}'
      SUCCEEDED_HOSTS=""
      FAILED_HOSTS=""
      HAD_WARNINGS=false
      ALL_STORE_PATHS=""
      attempt=0

      while [ -n "$PENDING" ] && [ $attempt -lt $MAX_RETRIES ]; do
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$MAX_RETRIES (targets: $PENDING)..."
        LOG=$(mktemp)
        colmena_exit=0
        PENDING_ARG=$(echo "$PENDING" | tr ' ' ',')
        ${pkgs.colmena}/bin/colmena apply --on "$PENDING_ARG" --parallel 4 switch 2>&1 | tee "$LOG" || colmena_exit=$?

        # Accumulate store paths and warnings across all attempts
        NEW_PATHS=$(grep -oE '/nix/store/[a-z0-9]+[^[:space:]]*' "$LOG" | sort -u || true)
        [ -n "$NEW_PATHS" ] && ALL_STORE_PATHS=$(printf '%s\n%s' "$ALL_STORE_PATHS" "$NEW_PATHS" | sort -u | grep -v '^$') || true
        grep -qE '\[WARN\]|warning:' "$LOG" && HAD_WARNINGS=true || true

        # Parse which hosts succeeded and which were targeted this round
        NEW_OK=$(grep 'Activation successful' "$LOG" | grep -oP '^\[\K[^\]]+' | sort -u || true)
        THIS_TARGETED=$(grep -oP '^\[\K[^\]]+(?=\] )' "$LOG" | grep -vxE 'INFO|WARN|ERROR|DEBUG' | sort -u || true)
        [ -n "$NEW_OK" ] && SUCCEEDED_HOSTS=$(printf '%s\n%s' "$SUCCEEDED_HOSTS" "$NEW_OK" | sort -u | grep -v '^$' | tr '\n' ' ' | xargs) || true

        if [ $colmena_exit -eq 0 ]; then
          rm "$LOG"
          PENDING=""
        else
          # Determine which hosts failed this round
          THIS_FAILED=$(comm -23 <(echo "$THIS_TARGETED" | grep -v '^$' | sort) <(echo "$NEW_OK" | grep -v '^$' | sort) 2>/dev/null || true)
          # Classify each failed host: connection error vs hard failure
          CONN_FAIL=""
          HARD_FAIL=""
          for h in $THIS_FAILED; do
            if grep -E "^\[$h\]" "$LOG" | grep -qE 'ssh: connect|Connection refused|No route to host|Connection timed out|Network is unreachable|Could not connect'; then
              CONN_FAIL=$(printf '%s\n%s' "$CONN_FAIL" "$h")
            else
              HARD_FAIL=$(printf '%s\n%s' "$HARD_FAIL" "$h")
            fi
          done
          CONN_FAIL=$(echo "$CONN_FAIL" | grep -v '^$' | sort -u | tr '\n' ' ' | xargs || true)
          HARD_FAIL=$(echo "$HARD_FAIL" | grep -v '^$' | sort -u | tr '\n' ' ' | xargs || true)
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          rm "$LOG"

          # Hard failures: notify immediately and abandon those hosts
          if [ -n "$HARD_FAIL" ]; then
            FAILED_HOSTS=$(printf '%s\n%s' "$FAILED_HOSTS" "$HARD_FAIL" | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u274c ${name} deploy FAILED ($HARD_FAIL)" \
              -p 10 \
              "Hard failure on: $HARD_FAIL\n\nLast 20 lines:\n$ERROR_SUMMARY"
          fi

          # Connection failures: retry if attempts remain, otherwise give up
          if [ -n "$CONN_FAIL" ]; then
            if [ $attempt -ge $MAX_RETRIES ]; then
              FAILED_HOSTS=$(printf '%s\n%s' "$FAILED_HOSTS" "$CONN_FAIL" | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
              ${pkgs.gotify-cli}/bin/gotify push \
                -t "\u274c ${name} deploy FAILED (retries exhausted)" \
                -p 10 \
                "Connection retries exhausted for: $CONN_FAIL"
              CONN_FAIL=""
            else
              echo "Connection failed for $CONN_FAIL, retrying in $((RETRY_DELAY / 60)) minutes (attempt $attempt/$MAX_RETRIES)..."
              sleep $RETRY_DELAY
            fi
          fi

          PENDING=$(echo "$CONN_FAIL" | xargs || true)
        fi
      done

      # Safety net in case the while condition killed the loop with PENDING still set
      if [ -n "$PENDING" ]; then
        FAILED_HOSTS=$(printf '%s\n%s' "$FAILED_HOSTS" "$PENDING" | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)
      fi
      FAILED_HOSTS=$(echo "$FAILED_HOSTS" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs || true)

      # Success notification and follow-up work for all hosts that deployed
      if [ -n "$SUCCEEDED_HOSTS" ]; then
        if [ -n "$FAILED_HOSTS" ]; then
          DEPLOY_SUMMARY="Succeeded: $SUCCEEDED_HOSTS\nFailed: $FAILED_HOSTS"
          TITLE_SUFFIX=" (partial)"
        else
          DEPLOY_SUMMARY="All targeted hosts deployed successfully."
          TITLE_SUFFIX=""
        fi
        if [ "$HAD_WARNINGS" = true ]; then
          ${pkgs.gotify-cli}/bin/gotify push \
            -t "\u26a0\ufe0f ${name} deploy''${TITLE_SUFFIX} succeeded (with warnings)" \
            -p 4 \
            "$DEPLOY_SUMMARY"
        else
          ${pkgs.gotify-cli}/bin/gotify push \
            -t "\u2705 ${name} deploy''${TITLE_SUFFIX} succeeded" \
            -p 3 \
            "$DEPLOY_SUMMARY"
        fi

        REVISIONS=""
        for host in $SUCCEEDED_HOSTS; do
          VER=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" nixos-version 2>/dev/null || echo "unreachable")
          REVISIONS+="$host: $VER\n"
        done
        COMMIT_MSG=$(printf 'auto: ${name} deploy %s\n\n%b' "$(date '+%Y-%m-%d %H:%M')" "$REVISIONS")
        ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
        ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true

        TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
        BASE_GCROOT_DIR=/nix/var/nix/gcroots/colmena-hosts
        mkdir -p "$BASE_GCROOT_DIR"
        for host in $SUCCEEDED_HOSTS; do
          HOST_DIR="$BASE_GCROOT_DIR/$host"
          mkdir -p "$HOST_DIR"
          for p in $ALL_STORE_PATHS; do
            if [ -e "$p" ]; then
              ROOT_FILE="$HOST_DIR/$TIMESTAMP-$(basename "$p")"
              ${pkgs.nix}/bin/nix-store --add-root "$ROOT_FILE" --indirect "$p" || true
            fi
          done
          KEEP=${toString keepRoots}
          ls -1 "$HOST_DIR" 2>/dev/null | sort -r | tail -n +$((KEEP+1)) | while read f; do
            rm -f "$HOST_DIR/$f" || true
          done || true
        done
        KNOWN_HOSTS=$(find "${repoPath}/hosts" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || true)
        for d in "$BASE_GCROOT_DIR"/*; do
          [ -d "$d" ] || continue
          host_dir_name=$(basename "$d")
          if ! echo "$KNOWN_HOSTS" | grep -xq "$host_dir_name"; then
            rm -rf "$d" || true
          fi
        done || true
      fi

      [ -z "$FAILED_HOSTS" ] || exit 1
    '';
  };

  mkSelfDeployService = selfHostname: {
    description = "Self Colmena Deploy";
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail

      echo "--- Updating flake ---"
      ${pkgs.nix}/bin/nix flake update --flake "${flakePath}"

      echo "--- Committing pre-deploy state ---"
      ${pkgs.git}/bin/git -C "${repoPath}" add -A
      ${pkgs.git}/bin/git -C "${repoPath}" commit -m "auto: Self pre-deploy $(date '+%Y-%m-%d %H:%M')" || true

      echo "--- Deploying Self (${selfHostname}) ---"
      RETRY_DELAY=300
      MAX_RETRIES=3
      for attempt in $(seq 1 $MAX_RETRIES); do
        echo "Attempt $attempt/$MAX_RETRIES..."
        LOG=$(mktemp)
        cd "${repoPath}"
        if ${pkgs.colmena}/bin/colmena apply-local switch 2>&1 | tee "$LOG"; then
          WARNINGS=$(grep -E '\[WARN\]|warning:' "$LOG" || true)
          if [ -n "$WARNINGS" ]; then
            MSG="Warnings:\n$WARNINGS"
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u26a0\ufe0f Self deploy succeeded (with warnings)" \
              -p 4 \
              "$MSG"
          else
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u2705 Self deploy succeeded" \
              -p 3 \
              "${selfHostname} deployed successfully."
          fi
          VER=$(nixos-version 2>/dev/null || echo "unknown")
          COMMIT_MSG=$(printf 'auto: Self deploy %s\n\n${selfHostname}: %s' "$(date '+%Y-%m-%d %H:%M')" "$VER")
          ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
          ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true
          # Keep GC roots for build outputs created during self deploy
          TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
          BASE_GCROOT_DIR=/nix/var/nix/gcroots/colmena-hosts
          mkdir -p "$BASE_GCROOT_DIR/self"
          STORE_PATHS=$(grep -oE '/nix/store/[a-z0-9]+[^[:space:]]*' "$LOG" | sort -u || true)
          for p in $STORE_PATHS; do
            if [ -e "$p" ]; then
              ROOT_FILE="$BASE_GCROOT_DIR/self/$TIMESTAMP-$(basename "$p")"
              ${pkgs.nix}/bin/nix-store --add-root "$ROOT_FILE" --indirect "$p" || true
            fi
          done
          KEEP=${toString keepRoots}
          ls -1 "$BASE_GCROOT_DIR/self" 2>/dev/null | sort -r | tail -n +$((KEEP+1)) | while read f; do
            rm -f "$BASE_GCROOT_DIR/self/$f" || true
          done || true
          rm "$LOG"
          break
        else
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          rm "$LOG"
          if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Deploy failed, retrying in $((RETRY_DELAY / 60)) minutes (attempt $attempt/$MAX_RETRIES)..."
            sleep $RETRY_DELAY
          else
            MSG="Last 20 lines of log:\n$ERROR_SUMMARY"
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u274c Self deploy FAILED" \
              -p 10 \
              "$MSG"
            exit 1
          fi
        fi
      done
    '';
  };

  deployCmd = pkgs.writeShellScriptBin "deploy" ''
    set -euo pipefail

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

    echo "--- Committing pre-deploy state ---"
    ${pkgs.git}/bin/git add -A
    ${pkgs.git}/bin/git commit -m "auto: manual deploy $TARGET $(date '+%Y-%m-%d %H:%M')" || true

    if [[ "$TARGET" == "$HOSTNAME" ]] || [[ "$TARGET" == "build-nix" && "$HOSTNAME" == "build-nix" ]]; then
      echo "--- Local deploy (apply-local $GOAL) ---"
      ${pkgs.colmena}/bin/colmena apply-local "$GOAL"
    else
      echo "--- Deploying $TARGET ($GOAL) ---"
      ${pkgs.colmena}/bin/colmena apply --on "$TARGET" --parallel 4 "$GOAL"
    fi
  '';

  deployOldCmd = pkgs.writeShellScriptBin "deploy-old" ''
    set -euo pipefail

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
    ${pkgs.openssh}/bin/ssh -o BatchMode=yes root@"$HOST" "sudo nix-env -p /nix/var/nix/profiles/system --switch-generation $GEN && sudo /nix/var/nix/profiles/system/activate" || {
      echo "Remote activation failed on $HOST. If the activation failed due to missing store paths, run 'nix copy' from a machine that has the closures.'"
      exit 1
    }

    echo "deploy-old completed for $HOST -> generation $GEN"
  '';

  mkTimer = name: onCalendar: {
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
    "deploy-Daily" = mkDeployService "Daily" "@daily";
    "deploy-Weekly" = mkDeployService "Weekly" "@weekly";
    "deploy-Monthly" = mkDeployService "Monthly" "@monthly";
    "deploy-Self" = mkSelfDeployService "build-nix";
  };

  systemd.timers = {
    "deploy-Daily" = mkTimer "Daily" "Sun,Mon..Fri *-*-* 00:00";
    "deploy-Weekly" = mkTimer "Weekly" "Sat *-*-8..31 00:00";
    "deploy-Monthly" = mkTimer "Monthly" "Sat *-*-1..7 00:00";
    "deploy-Self" = mkTimer "Self" "Sat *-*-* 01:00";
  };
}
