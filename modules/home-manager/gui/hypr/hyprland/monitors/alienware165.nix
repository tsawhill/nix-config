{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.alienware165.enable = lib.mkEnableOption "desktop monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.alienware165.enable {

    # Lua owns this monitor's rule so a fixed HDR/165 Hz rule cannot override
    # the split-screen profile. Also works over HDMI, which advertises 100 Hz.
    wayland.windowManager.hyprland.extraConfig = builtins.readFile ./alienware165.lua;
  };
}
