{
  # window rules for floating inactive window
  wayland.windowManager.hyprland.settings.windowrulev2 = [
    "opacity 1.0 0.95, class:.+"
    "opacity 1.0 1.0, title:^(.*- YouTube — Ablaze Floorp)$"
    "opacity 1.0 1.0, class:^(foot)$"
  ];
}
