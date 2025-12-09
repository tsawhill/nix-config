{
  # Gaming window rules (no idle, tearing)
  wayland.windowManager.hyprland.settings.windowrule = [
    "idle_inhibit focus,match:class gamescope"
    "content game, match:class gamescope"
    "immediate on, match:class gamescope"
    "immediate on, match:class cs2"
    "immediate on, match:content game"
    # "immediate, focus:1"
  ];
}
