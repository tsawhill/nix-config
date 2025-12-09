{
  # Window rules for floating slideout bluetooth control from taskbar
  wayland.windowManager.hyprland.settings.windowrule = [
    "float on,match:class .blueman-manager-wrapped"
    "size 700 700,match:class .blueman-manager-wrapped"
    "move 100%-705 60,match:class .blueman-manager-wrapped"
    "animation slide,match:class .blueman-manager-wrapped"
  ];
}
