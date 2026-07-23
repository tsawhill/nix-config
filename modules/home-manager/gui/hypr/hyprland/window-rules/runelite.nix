{ config, lib, ... }:
{
  options.my.hypr.windowRules.runelite.enable = lib.mkEnableOption "runelite window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.runelite.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # Bolt Launcher
      {
        match = { class = "BoltLauncher"; };
        float = true;
        size = "1115 894";
      }

      # RuneLite Launcher (update/splash screen)
      {
        match = { class = "net-runelite-launcher-Launcher"; };
        float = true;
        size = "640 480";
      }

      # RuneLite client — float all windows; size only the main client, not popups
      {
        match = { class = "net-runelite-client-RuneLite"; };
        float = true;
        pseudo = true;
      }
      {
        match = {
          class = "net-runelite-client-RuneLite";
          title = "^RuneLite$";
        };
        size = "1078 777";
      }
      # XWayland popups (titled win* by Java): suppress focus fighting and fix black rendering
      {
        match = {
          class = "net-runelite-client-RuneLite";
          title = "^win";
        };
        suppress_event = "activatefocus";
        no_initial_focus = true;
        immediate = true;
        render_unfocused = true;
        focus_on_activate = false;
      }
    ];
  };
}
