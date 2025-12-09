{
  # Window rules for floating slideout connection editor from taskbar
  wayland.windowManager.hyprland.settings.windowrule = [
    "float,class:^(nm-connection-editor)$"
    "size 700 700,class:^(nm-connection-editor)$"
    "move 100%-705 60,class:^(nm-connection-editor)$"
    "animation slide,class:^(nm-connection-editor)$"
  ];
}
