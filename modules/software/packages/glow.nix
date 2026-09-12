{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.software.glow.enable = lib.mkEnableOption "glow transfer dashboard";

  config = lib.mkIf config.software.glow.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "glow";
        runtimeInputs = [
          pkgs.rsync
          pkgs.openssh
        ];
        text = ''
          exec ${
            pkgs.python3.withPackages (ps: [ ps.rich ])
          }/bin/python3 ${../../../pkgs/glow/glow.py} "$@"
        '';
      })
    ];
  };
}
