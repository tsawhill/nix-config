{ config, lib, ... }:
# Generates float + size + position + slide animation rules for taskbar slideout popups.
# Add to config.my.hypr.taskbarPopups from any module/host — definitions are concatenated.
let
  mkPopupRules = class: [
    "float on,match:class ${class}"
    "size 700 700,match:class ${class}"
    "move (monitor_w-705) 60,match:class ${class}"
    "animation taskbarPopup,match:class ${class}"  # Custom snappy bezier, defined below
    "rounding 16,match:class ${class}"             # Rounder than global default (5)
    "opacity 0.88 0.88,match:class ${class}"       # Frosted glass — pairs with global blur
    "dimaround,match:class ${class}"               # Dims everything else for a spotlight effect
    "bordercolor rgba(ffcce6ff) rgba(9778D0ff) 45deg,match:class ${class}" # Pink/purple gradient border
  ];
in
{
  options.my.hypr.taskbarPopups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Window classes to treat as taskbar slideout popups (float, sized, positioned, slide animation).";
  };

  config = {
    my.hypr.taskbarPopups = [
      ".blueman-manager-wrapped"
      "org.pulseaudio.pavucontrol"
      "nm-connection-editor"
    ];

    # Custom easeOutExpo bezier: instant start, glides to a smooth stop
    wayland.windowManager.hyprland.settings.animations.bezier = [
      "popupEase, 0.16, 1, 0.3, 1"
    ];
    wayland.windowManager.hyprland.settings.animations.animation = [
      "taskbarPopup, 1, 4, popupEase, slide"
    ];

    wayland.windowManager.hyprland.settings.windowrule =
      lib.concatMap mkPopupRules config.my.hypr.taskbarPopups;
  };
}
