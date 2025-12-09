{
  # window rules for steam floating windows
  wayland.windowManager.hyprland.settings.windowrule = [
    "minsize 1 1, title:^()$,class:^(steam)$"
    "stayfocused, title:^()$,class:^(steam)$"
    "idleinhibit none,class:^(steam)$"
  ];
}
