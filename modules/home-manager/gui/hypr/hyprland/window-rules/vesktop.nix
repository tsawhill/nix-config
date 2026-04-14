{ config, lib, ... }:
{
  options.my.hypr.windowRules.vesktop.enable = lib.mkEnableOption "vesktop window rules" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.windowRules.vesktop.enable {
    wayland.windowManager.hyprland.settings.windowrule = [
      "suppress_event fullscreen fullscreenoutput, match:class vesktop"
    ];
  };
}
