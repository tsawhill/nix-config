{ config, lib, ... }:
{
  options.my.hypr.windowRules.gaming.enable = lib.mkEnableOption "gaming window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.gaming.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      {
        match = { class = "gamescope"; };
        idle_inhibit = "focus";
        content = "game";
        immediate = true;
      }
      {
        match = { class = "cs2"; };
        immediate = true;
      }
      {
        match = { content = "game"; };
        immediate = true;
      }
    ];
  };
}
