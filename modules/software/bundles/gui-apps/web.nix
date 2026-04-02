{
  pkgs,
  lib,
  config,
  inputs,
  zen-input,
  ...
}:
{
  options.software.apps.web.enable = lib.mkEnableOption "web browsers and related tools";

  config = lib.mkIf config.software.apps.web.enable {
    environment.systemPackages = with pkgs; [
      zen-input.packages.${pkgs.stdenv.hostPlatform.system}.default
      bitwarden-desktop
    ];
  };
}
