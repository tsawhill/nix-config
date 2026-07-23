{ config, lib, ... }:
{
  options.my.hypr.windowRules.steam.enable = lib.mkEnableOption "steam window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.steam.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # Suppress steam from stealing focus
      {
        match = { class = "steam"; };
        suppress_event = "activatefocus";
        no_initial_focus = true;
      }

      # Notification toasts — block idle inhibition and focus grabs
      {
        match = {
          class = "steam";
          title = "^notificationtoasts";
        };
        idle_inhibit = "none";
        suppress_event = "activatefocus";
        no_initial_focus = true;
      }

      # Fallback: any steam window except notification toasts — catches chat/DMs where title is dynamic.
      # More specific rules below override position/size for library and friends list.
      # Percentages are relative to the window's current monitor so layout scales
      # correctly across monitors of different resolutions (e.g. ultrawide after swap).
      {
        match = {
          class = "steam";
          title = "negative:^notificationtoasts";
        };
        float = true;
        move = "61% 5%";
        size = "38% 47%";
      }

      # Steam library (main window) — overrides fallback
      {
        match = {
          class = "steam";
          title = "^Steam$";
        };
        move = "1% 6%";
        size = "56% 88%";
      }

      # Steam friends list — overrides fallback
      {
        match = {
          class = "steam";
          title = "^Friends List$";
        };
        move = "66% 55%";
        size = "30% 43%";
      }
    ];
  };
}
