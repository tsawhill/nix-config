{
  # Window rules for floating slideout connection editor from taskbar
  wayland.windowManager.hyprland.settings.windowrule = [
    "float on,match:class nm-connection-editor"
    "size 700 700,match:class nm-connection-editor"
    "move (monitor_w-705) 60,match:class nm-connection-editor"
    "animation slide,match:class nm-connection-editor"
  ];
}
