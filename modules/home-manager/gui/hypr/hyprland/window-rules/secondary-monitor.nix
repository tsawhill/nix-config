{ config, lib, ... }:
{
  options.my.hypr.windowRules.secondaryMonitor.enable = lib.mkEnableOption "secondary monitor window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.secondaryMonitor.enable {
    wayland.windowManager.hyprland.settings.windowrule = [
      # vesktop — master window on workspace 6
      "pseudo on, match:class vesktop"
      "size 2123 1209, match:class vesktop"

      # feishin — slave window on workspace 6
      "pseudo on, match:class feishin"
      "size 907 921, match:class feishin"
    ];
  };
}
