{ config, lib, ... }:
{
  options.my.hypr.windowRules.gaming.enable = lib.mkEnableOption "gaming window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.gaming.enable {
    wayland.windowManager.hyprland.settings.windowrule = [
      "idle_inhibit focus,match:class gamescope"
      "content game, match:class gamescope"
      "immediate on, match:class gamescope"
      "immediate on, match:class cs2"
      "immediate on, match:content game"
    ];
  };
}
