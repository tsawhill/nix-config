{
  wayland.windowManager.hyprland.settings.windowrule = [
    "float, match:class net-runelite-client-RuneLite"
    # Size rule only for the main client, not popups
    "size 1078 777, match:class net-runelite-client-RuneLite, match:title ^RuneLite$"
  ];
}
