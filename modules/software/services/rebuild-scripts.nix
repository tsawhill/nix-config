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
      for attempt in $(seq 1 $MAX_RETRIES); do
        echo "Attempt $attempt/$MAX_RETRIES..."
        LOG=$(mktemp)
        if ${pkgs.colmena}/bin/colmena apply --on '${tags}' --parallel 4 switch 2>&1 | tee "$LOG"; then
          WARNINGS=$(grep -E '\[WARN\]|warning:' "$LOG" || true)
          if [ -n "$WARNINGS" ]; then
            MSG="Warnings:\n$WARNINGS"
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u26a0\ufe0f ${name} deploy succeeded (with warnings)" \
              -p 4 \
              "$MSG"
          else
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u2705 ${name} deploy succeeded" \
              -p 3 \
              "All targeted hosts deployed successfully."
          fi
          REVISIONS=""
          HOSTS=$(grep 'Activation successful' "$LOG" | grep -oP '^\[\K[^\]]+' || true)
          for host in $HOSTS; do
            VER=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" nixos-version 2>/dev/null || echo "unreachable")
            REVISIONS+="$host: $VER\n"
          done
          COMMIT_MSG=$(printf 'auto: ${name} deploy %s\n\n%b' "$(date '+%Y-%m-%d %H:%M')" "$REVISIONS")
          ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
          ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true
          # Keep recent build/store outputs as indirect GC roots so they
          # survive garbage collection on the build host. We keep a small
          # number of recent roots and prune older ones automatically.
          TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
          BASE_GCROOT_DIR=/nix/var/nix/gcroots/colmena-hosts
          mkdir -p "$BASE_GCROOT_DIR"
          # collect unique /nix/store paths from the colmena log
          STORE_PATHS=$(grep -oE '/nix/store/[a-z0-9]+[^[:space:]]*' "$LOG" | sort -u || true)
          # create per-host gcroots so we can keep/prune per-host and detect removed hosts
          for host in $HOSTS; do
            HOST_DIR="$BASE_GCROOT_DIR/$host"
            mkdir -p "$HOST_DIR"
            for p in $STORE_PATHS; do
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
          # remove GC root dirs for hosts removed from the repo
          KNOWN_HOSTS=$(find "${repoPath}/hosts" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || true)
          for d in "$BASE_GCROOT_DIR"/*; do
            [ -d "$d" ] || continue
            host_dir_name=$(basename "$d")
            if ! echo "$KNOWN_HOSTS" | grep -xq "$host_dir_name"; then
              rm -rf "$d" || true
            fi
          done || true
          rm "$LOG"
          break
        else
          ERROR_SUMMARY=$(tail -n 20 "$LOG")
          if grep -qE 'ssh: connect|Connection refused|No route to host|Connection timed out|Network is unreachable|Could not connect' "$LOG"; then
            rm "$LOG"
            if [ $attempt -ge $MAX_RETRIES ]; then
              MSG="Last 20 lines of log:\n$ERROR_SUMMARY"
              ${pkgs.gotify-cli}/bin/gotify push \
                -t "\u274c ${name} deploy FAILED (connection retries exhausted)" \
                -p 10 \
                "$MSG"
              exit 1
            fi
            echo "Connection failed, retrying in $((RETRY_DELAY / 60)) minutes (attempt $attempt/$MAX_RETRIES)..."
            sleep $RETRY_DELAY
          else
            rm "$LOG"
            MSG="Last 20 lines of log:\n$ERROR_SUMMARY"
            ${pkgs.gotify-cli}/bin/gotify push \
              -t "\u274c ${name} deploy FAILED" \
              -p 10 \
              "$MSG"
            exit 1
          fi
        fi
      done
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
