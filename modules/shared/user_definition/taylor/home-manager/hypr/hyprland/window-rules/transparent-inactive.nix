{
  # window rules for floating inactive window
  wayland.windowManager.hyprland.settings.windowrulev2 = [
    "opacity 1.0 0.90, class:.+"
    "opacity 1.0 1.0, title:^(.*- YouTube — Ablaze Floorp)$"
    "opacity 1.0 1.0, title:^(.*tv — Ablaze Floorp)$"
    "opacity 1.0 1.0, title:^(.*Kick — Ablaze Floorp)$"
    "opacity 1.0 0.8, class:^(foot)$"
    "opacity 1.0 0.8, class:^(vesktop)$"
    "opacity 1.0 0.8, class:^(feishin)$"
    "opacity 1.0 1.0, class:^(cafe.avery.Delfin)$"
  ];
}
