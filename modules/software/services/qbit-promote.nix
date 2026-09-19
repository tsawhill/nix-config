{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.qbit-promote;

  # Wired into Sonarr/Radarr/Lidarr as an On Import Custom Script. The *arrs need
  # an absolute path, so this lands at /run/current-system/sw/bin/qbit-promote.
  promote = pkgs.writeShellScriptBin "qbit-promote" ''
    export QBIT_INTAKE_URL=${lib.escapeShellArg cfg.intakeUrl}
    export QBIT_SEEDING_URL=${lib.escapeShellArg cfg.seedingUrl}
    exec ${pkgs.python3}/bin/python3 ${../../../pkgs/qbittorrent/qbit_promote.py} "$@"
  '';
in
{
  options.my.services.qbit-promote = {
    enable = lib.mkEnableOption "the qBittorrent intake-to-seeding promotion script";

    intakeUrl = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the intake qBittorrent web UI.";
    };

    seedingUrl = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the seeding qBittorrent web UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ promote ];
  };
}
