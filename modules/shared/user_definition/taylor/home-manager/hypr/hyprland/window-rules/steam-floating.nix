{
  # window rules for steam floating windows
  wayland.windowManager.hyprland.settings.windowrule = [
    "minsize 1 1, title:^()$,match:class steam"
    "stayfocused, title:^()$,match:class steam"
    "idle_inhibit none,match:class steam"
  ];
}
