{
  config,
  lib,
  pkgs,
  ...
}:
let
  qbitPromoteMissed = pkgs.callPackage ../../../pkgs/qbittorrent/promote-missed.nix { };
  promote = config.my.services.qbit-promote;
  keyFile = name: config.sops.secrets."${name}_api_key".path;
in
{
  options.software.qbit-promote-missed.enable =
    lib.mkEnableOption "catch-up for imports qbit-promote failed to promote";

  config = lib.mkIf config.software.qbit-promote-missed.enable {
    assertions = [
      {
        assertion = promote.enable;
        message = "software.qbit-promote-missed reuses my.services.qbit-promote's URLs; enable it too.";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "qbit-promote-missed";
        text = ''
          export QBIT_INTAKE_URL=${lib.escapeShellArg promote.intakeUrl}
          export QBIT_SEEDING_URL=${lib.escapeShellArg promote.seedingUrl}
          export SONARR_API_KEY_FILE=${keyFile "sonarr"}
          export RADARR_API_KEY_FILE=${keyFile "radarr"}
          export LIDARR_API_KEY_FILE=${keyFile "lidarr"}
          exec ${lib.getExe qbitPromoteMissed} "$@"
        '';
      })
    ];
  };
}
