{
  # Gaming window rules (no idle, tearing)
  wayland.windowManager.hyprland.settings.windowrulev2 = [
    "idleinhibit focus,class:^(gamescope)$"
    "immediate, class:^(gamescope)$"
    "immediate, class:^(cs2)$"
    # "immediate, focus:1"
  ];
}
