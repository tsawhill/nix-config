{
  # Do not let steam windows take focus
  wayland.windowManager.hyprland.settings.windowrule = [
    "suppress_event activatefocus, match:class steam"
    "no_initial_focus on, match:class steam"
  ];
}
