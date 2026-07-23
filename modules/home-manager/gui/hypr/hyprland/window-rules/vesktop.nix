{ config, lib, ... }:
{
  options.my.hypr.windowRules.vesktop.enable = lib.mkEnableOption "vesktop window rules" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.windowRules.vesktop.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      {
        match = { class = "vesktop"; };
        suppress_event = "fullscreen fullscreenoutput";
      }
    ];
  };
}
