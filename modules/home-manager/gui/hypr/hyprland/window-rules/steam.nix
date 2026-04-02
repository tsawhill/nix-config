{
  wayland.windowManager.hyprland.settings.windowrule = [
    # Suppress steam from stealing focus
    "suppress_event activatefocus, match:class steam"
    "no_initial_focus on, match:class steam"
  ];
}
