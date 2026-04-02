{ pkgs, ... }:

let
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
      LOG=$(mktemp)
      if ${pkgs.colmena}/bin/colmena apply --flake "${flakePath}" --on '${tags}' --parallel 4 switch 2>&1 | tee "$LOG"; then
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
          VER=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "root@''${host}" nixos-version 2>/dev/null || echo "unreachable")
          REVISIONS+="''${host}: ''${VER}\n"
        done
        COMMIT_MSG=$(printf 'auto: ${name} deploy %s\n\n%b' "$(date '+%Y-%m-%d %H:%M')" "$REVISIONS")
        ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
        ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true
      else
        ERROR_SUMMARY=$(tail -n 20 "$LOG")
        MSG="Last 20 lines of log:\n$ERROR_SUMMARY"
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u274c ${name} deploy FAILED" \
          -p 10 \
          "$MSG"
        rm "$LOG"
        exit 1
      fi
      rm "$LOG"
    '';
  };

  mkSelfDeployService = {
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

      echo "--- Deploying Self (build-nix) ---"
      LOG=$(mktemp)
      if cd "${repoPath}" && ${pkgs.colmena}/bin/colmena apply-local switch 2>&1 | tee "$LOG"; then
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
            "build-nix deployed successfully."
        fi
        VER=$(nixos-version 2>/dev/null || echo "unknown")
        COMMIT_MSG=$(printf 'auto: Self deploy %s\n\nbuild-nix: %s' "$(date '+%Y-%m-%d %H:%M')" "$VER")
        ${pkgs.git}/bin/git -C "${repoPath}" add flake.lock
        ${pkgs.git}/bin/git -C "${repoPath}" commit -m "$COMMIT_MSG" || true
      else
        ERROR_SUMMARY=$(tail -n 20 "$LOG")
        MSG="Last 20 lines of log:\n$ERROR_SUMMARY"
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u274c Self deploy FAILED" \
          -p 10 \
          "$MSG"
        rm "$LOG"
        exit 1
      fi
      rm "$LOG"
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

    if [[ "$TARGET" == "$HOSTNAME" ]] || [[ "$TARGET" == "build-nix" && "$HOSTNAME" == "build-nix" ]]; then
      echo "--- Local deploy (apply-local $GOAL) ---"
      ${pkgs.colmena}/bin/colmena apply-local "$GOAL"
    else
      echo "--- Deploying $TARGET ($GOAL) ---"
      ${pkgs.colmena}/bin/colmena apply --on "$TARGET" "$GOAL"
    fi
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
  environment.systemPackages = [ deployCmd ];

  systemd.services = {
    "deploy-Daily" = mkDeployService "Daily" "@daily";
    "deploy-Weekly" = mkDeployService "Weekly" "@daily,@weekly";
    "deploy-Monthly" = mkDeployService "Monthly" "@daily,@weekly,@monthly";
    "deploy-Self" = mkSelfDeployService;
  };

  systemd.timers = {
    "deploy-Daily" = mkTimer "Daily" "Sun,Mon..Fri *-*-* 00:00";
    "deploy-Weekly" = mkTimer "Weekly" "Sat *-*-8..31 00:00";
    "deploy-Monthly" = mkTimer "Monthly" "Sat *-*-1..7 00:00";
    "deploy-Self" = mkTimer "Self" "Sat *-*-* 01:00";
  };
}
