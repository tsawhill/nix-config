{ lib, config, ... }:
{
  options.my.hypr.monitors.dellS2721dgf.enable = lib.mkEnableOption "Dell S2721DGF monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.dellS2721dgf.enable {
    wayland.windowManager.hyprland.settings.monitor = [
      {
        output = "desc:Dell Inc. DELL S2721DGF 98T9623";
        mode = "2560x1440@60.00Hz";
        position = "auto-right";
        scale = 1;
        vrr = 1;
      }
    ];
  };
}
