{
  # Window rules for floating slideout volume control from taskbar
  wayland.windowManager.hyprland.settings.windowrule = [
    "float,class:^(org.pulseaudio.pavucontrol)$"
    "size 700 700,class:^(org.pulseaudio.pavucontrol)$"
    "move 100%-705 60,class:^(org.pulseaudio.pavucontrol)$"
    "animation slide,class:^(org.pulseaudio.pavucontrol)$"
  ];
}
