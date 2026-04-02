{ pkgs, lib, config, ... }:
{
  options.software.apps.config.enable = lib.mkEnableOption "desktop configuration tools";

  config = lib.mkIf config.software.apps.config.enable {
    environment.systemPackages = with pkgs; [
      foot
      networkmanagerapplet
      easyeffects
      pavucontrol
      nwg-look
      dconf-editor
    ];
  };
}
