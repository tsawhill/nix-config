{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.fallback.enable = lib.mkEnableOption "Fallback monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.fallback.enable {

    wayland.windowManager.hyprland.settings.monitor = [
      {
        output = "HDMI-A-1";
        mode = "highrr";
        position = "auto";
        scale = 1;
      }
    ];
  };
}
