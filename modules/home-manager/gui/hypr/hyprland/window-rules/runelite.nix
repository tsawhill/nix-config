{
  wayland.windowManager.hyprland.settings.windowrule = [
    # Bolt Launcher
    "float on, match:class BoltLauncher"
    "size 1115 894, match:class BoltLauncher"

    # RuneLite Launcher (update/splash screen)
    "float on, match:class net-runelite-launcher-Launcher"
    "size 640 480, match:class net-runelite-launcher-Launcher"

    # RuneLite client (float all windows; size only the main client, not popups)
    "float on, match:class net-runelite-client-RuneLite"
    "size 1078 777, match:class net-runelite-client-RuneLite, match:title ^RuneLite$"
    # Suppress focus fighting on XWayland popups (titled win* by Java)
    "suppress_event activatefocus, match:class net-runelite-client-RuneLite, match:title ^win"
    "no_initial_focus on, match:class net-runelite-client-RuneLite, match:title ^win"
    # Fix black popup rendering on XWayland
    "immediate on, match:class net-runelite-client-RuneLite, match:title ^win"
    "renderunfocused on, match:class net-runelite-client-RuneLite, match:title ^win"
  ];
}
