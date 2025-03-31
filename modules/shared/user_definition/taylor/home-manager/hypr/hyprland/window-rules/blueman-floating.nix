{
  # Window rules for floating slideout bluetooth control from taskbar
  wayland.windowManager.hyprland.settings.windowrulev2 = [
    "float,class:^(.blueman-manager-wrapped)$"
    "size 700 700,class:^(.blueman-manager-wrapped)$"
    "move 100%-705 60,class:^(.blueman-manager-wrapped)$"
    "animation slide,class:^(.blueman-manager-wrapped)$"
  ];
}
