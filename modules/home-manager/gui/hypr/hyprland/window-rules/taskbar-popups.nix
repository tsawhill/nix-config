{ config, lib, ... }:
# Generates float + size + position + slide animation rules for taskbar slideout popups.
# Add to config.my.hypr.taskbarPopups from any module/host — definitions are concatenated.
let
  mkPopupRules = class: [
    {
      match = { class = class; };
      float = true;
      size = "700 700";
      move = "(monitor_w-705) 60";
      rounding = 16; # Rounder than global default (5)
      opacity = "0.88 0.88"; # Frosted glass — pairs with global blur
      border_color = "rgba(ffcce6ff) rgba(9778D0ff) 45deg"; # Pink/purple gradient border
      animation = "slide right"; # Slide in from right using global overshoot bezier
    }
  ];
in
{
  options.my.hypr.windowRules.taskbarPopups.enable = lib.mkEnableOption "taskbar popup window rules" // { default = true; };

  options.my.hypr.taskbarPopups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Window classes to treat as taskbar slideout popups (float, sized, positioned, slide animation).";
  };

  config = lib.mkIf config.my.hypr.windowRules.taskbarPopups.enable {
    my.hypr.taskbarPopups = [
      ".blueman-manager-wrapped"
      "org.pulseaudio.pavucontrol"
      "nm-connection-editor"
    ];


    wayland.windowManager.hyprland.settings.window_rule =
      lib.concatMap mkPopupRules config.my.hypr.taskbarPopups;
  };
}
