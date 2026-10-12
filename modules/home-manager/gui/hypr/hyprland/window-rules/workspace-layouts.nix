{ config, lib, ... }:
{
  wayland.windowManager.hyprland.extraConfig = ''
    dofile("${./workspace-layouts.lua}")(
      ${lib.boolToString config.my.hypr.windowRules.steam.enable},
      ${lib.boolToString config.my.hypr.windowRules.secondaryMonitor.enable}
    )
  '';
}
