{
  # Window rules for pseudotiled always-on apps for 2nd monitor
  wayland.windowManager.hyprland.settings.windowrule = [
    "pseudo,match:class vesktop"
    "size 1920 1080,match:class vesktop"

    "pseudo,match:class feishin"
    "size 1000 1000,match:class feishin"
  ];
}
