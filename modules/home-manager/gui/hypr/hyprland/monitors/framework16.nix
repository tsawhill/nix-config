{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.framework16.enable = lib.mkEnableOption "Framework 16 monitor config";

  config = lib.mkIf config.my.hypr.monitors.framework16.enable {
    wayland.windowManager.hyprland.extraConfig = ''
      monitorv2 {
        output=eDP-1
        mode=2560x1600@165Hz
        position=0x0
        scale=1.333
      }
    '';
    wayland.windowManager.hyprland.settings.xwayland.force_zero_scaling = true;
  };
}
