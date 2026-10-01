{
  config,
  lib,
  pkgs,
  ...
}:
let
  glow = pkgs.callPackage ../../../pkgs/glow { };
in
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
        text = ''exec ${lib.getExe glow} "$@"'';
      })
    ];
  };
}
