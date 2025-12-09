{
  # Gaming window rules (no idle, tearing)
  wayland.windowManager.hyprland.settings.windowrule = [
    "idleinhibit focus,match:class gamescope"
    "content game, match:class gamescope"
    "immediate, match:class gamescope"
    "immediate, match:class cs2"
    "immediate, match:content game"
    # "immediate, focus:1"
  ];
}
