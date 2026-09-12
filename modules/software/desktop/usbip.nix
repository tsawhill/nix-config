{ config, lib, ... }:
{
  imports = [ ../services/usbip-tray.nix ];
  my.usbip.enable = lib.mkDefault (config.desktop.hyprland.enable or false);
}
