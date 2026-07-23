{ config, lib, ... }:
{
  options.my.hypr.windowRules.secondaryMonitor.enable = lib.mkEnableOption "secondary monitor window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.secondaryMonitor.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # vesktop — master window on workspace 6
      {
        match = { class = "vesktop"; };
        pseudo = true;
        size = "2123 1209";
      }
      # feishin — slave window on workspace 6
      {
        match = { class = "feishin"; };
        pseudo = true;
        size = "907 921";
      }
    ];
  };
}
