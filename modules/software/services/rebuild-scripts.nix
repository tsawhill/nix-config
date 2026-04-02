{ pkgs, ... }:

let
  flakePath = "path:///mnt/zpool/code/nix-config";

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

      echo "--- Deploying ${name} (${tags}) ---"
      if ${pkgs.colmena}/bin/colmena apply --flake "${flakePath}" --on '${tags}' --parallel 4 switch; then
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u2705 ${name} deploy succeeded" \
          -p 3 \
          "All targeted hosts deployed successfully."
      else
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u274c ${name} deploy FAILED" \
          -p 10 \
          "colmena apply exited non-zero for ${name}. Check: journalctl -u deploy-${name}"
        exit 1
      fi
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

      echo "--- Deploying Self (build-nix) ---"
      if ${pkgs.colmena}/bin/colmena apply-local --flake "${flakePath}" switch; then
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u2705 Self deploy succeeded" \
          -p 3 \
          "build-nix deployed successfully."
      else
        ${pkgs.gotify-cli}/bin/gotify push \
          -t "\u274c Self deploy FAILED" \
          -p 10 \
          "colmena apply-local exited non-zero. Check: journalctl -u deploy-Self"
        exit 1
      fi
    '';
  };

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
  systemd.services = {
    "deploy-Daily"   = mkDeployService "Daily"   "@daily";
    "deploy-Weekly"  = mkDeployService "Weekly"  "@daily,@weekly";
    "deploy-Monthly" = mkDeployService "Monthly" "@daily,@weekly,@monthly";
    "deploy-Self"    = mkSelfDeployService;
  };

  systemd.timers = {
    "deploy-Daily"   = mkTimer "Daily"   "Sun,Mon..Fri *-*-* 00:00";
    "deploy-Weekly"  = mkTimer "Weekly"  "Sat *-*-8..31 00:00";
    "deploy-Monthly" = mkTimer "Monthly" "Sat *-*-1..7 00:00";
    "deploy-Self"    = mkTimer "Self"    "Sat *-*-* 01:00";
  };
}
