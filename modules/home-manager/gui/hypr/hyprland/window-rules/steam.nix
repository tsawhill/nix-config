{ config, lib, ... }:
{
  options.my.hypr.windowRules.steam.enable = lib.mkEnableOption "steam window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.steam.enable {
    wayland.windowManager.hyprland.settings.windowrule = [
      # Suppress steam from stealing focus
      "suppress_event activatefocus, match:class steam"
      "no_initial_focus on, match:class steam"

      # Notification toasts — block idle inhibition and focus grabs
      "idle_inhibit none, match:class steam, match:title ^notificationtoasts"
      "suppress_event activatefocus, match:class steam, match:title ^notificationtoasts"
      "no_initial_focus on, match:class steam, match:title ^notificationtoasts"

      # Fallback: any steam window except notification toasts — catches chat/DMs where title is dynamic
      # More specific rules below override position/size for library and friends list.
      # Percentages are relative to the window's current monitor so layout scales
      # correctly across monitors of different resolutions (e.g. ultrawide after swap).
      "float on, match:class steam, match:title negative:^notificationtoasts"
      "move 61% 5%, match:class steam, match:title negative:^notificationtoasts"
      "size 38% 47%, match:class steam, match:title negative:^notificationtoasts"

      # Steam library (main window) — overrides fallback
      "move 1% 6%, match:class steam, match:title ^Steam$"
      "size 56% 88%, match:class steam, match:title ^Steam$"

      # Steam friends list — overrides fallback
      "move 66% 55%, match:class steam, match:title ^Friends List$"
      "size 30% 43%, match:class steam, match:title ^Friends List$"
    ];
  };
}
