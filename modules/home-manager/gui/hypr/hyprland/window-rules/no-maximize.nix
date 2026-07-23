{ config, lib, ... }:
{
  options.my.hypr.windowRules.noMaximize.enable = lib.mkEnableOption "suppress maximize on all windows" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.noMaximize.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      {
        match = { class = ".*"; };
        suppress_event = "maximize";
      }
    ];
  };
}
