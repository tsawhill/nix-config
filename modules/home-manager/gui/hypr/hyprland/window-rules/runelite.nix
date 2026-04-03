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
    # Allow Java to manage its own window positions freely
    "windowdance on, match:class net-runelite-client-RuneLite"
    # Suppress focus fighting on XWayland popups (titled win* by Java)
    "suppressevent focus activate, match:class net-runelite-client-RuneLite, match:title ^win"
    "noinitialfocus on, match:class net-runelite-client-RuneLite, match:title ^win"
  ];
}
