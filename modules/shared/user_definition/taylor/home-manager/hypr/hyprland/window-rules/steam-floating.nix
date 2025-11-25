{
  # window rules for steam floating windows
  wayland.windowManager.hyprland.settings.windowrulev2 = [
    "minsize 1 1, title:^()$,class:^(steam)$"
    "stayfocused, title:^()$,class:^(steam)$"
    "idleinhibit none,class:^(steam)$"
  ];
}
