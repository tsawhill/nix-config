{ config, lib, ... }:
{
  options.my.hypr.windowRules.secondaryMonitor.enable = lib.mkEnableOption "secondary monitor window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.secondaryMonitor.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # Keep Vesktop's preferred content size inside the remaining tile.
      {
        match = { class = "vesktop"; };
        pseudo = true;
        size = "2123 1209";
      }
      {
        match = {
          class = "^com\\.moonlight_stream\\.Moonlight$";
          title = "(?i).*runelite.* - Moonlight$";
        };
        workspace = "6 silent";
        float = false;
        pseudo = true;
        size = "1180 820";
        suppress_event = "fullscreen maximize";
      }
    ];
  };
}
