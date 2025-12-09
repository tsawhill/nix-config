{
  # Window rules for floating slideout volume control from taskbar
  wayland.windowManager.hyprland.settings.windowrule = [
    "float on,match:class org.pulseaudio.pavucontrol"
    "size 700 700,match:class org.pulseaudio.pavucontrol"
    "move 100%-705 60,match:class org.pulseaudio.pavucontrol"
    "animation slide,match:class org.pulseaudio.pavucontrol"
  ];
}
