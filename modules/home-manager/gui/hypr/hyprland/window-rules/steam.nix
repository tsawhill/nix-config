{ config, lib, ... }:
{
  options.my.hypr.windowRules.steam.enable = lib.mkEnableOption "steam window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.steam.enable {
    wayland.windowManager.hyprland.settings.windowrule = [
      # Suppress steam from stealing focus
      "suppress_event activatefocus, match:class steam"
      "no_initial_focus on, match:class steam"

      # Notification toasts — block idle inhibition and focus grabs
      "idle_inhibit never, match:class steam, match:title ^notificationtoasts"
      "suppress_event activatefocus, match:class steam, match:title ^notificationtoasts"
      "no_initial_focus on, match:class steam, match:title ^notificationtoasts"

      # Fallback: any steam window except notification toasts — catches chat/DMs where title is dynamic
      # More specific rules below override position/size for library and friends list
      "float on, match:class steam, match:title negative:^notificationtoasts"
      "move 1561 71, match:class steam, match:title negative:^notificationtoasts"
      "size 973 684, match:class steam, match:title negative:^notificationtoasts"

      # Steam library (main window) — overrides fallback
      "move 13 86, match:class steam, match:title ^Steam$"
      "size 1430 1260, match:class steam, match:title ^Steam$"

      # Steam friends list — overrides fallback
      "move 1696 790, match:class steam, match:title ^Friends List$"
      "size 755 622, match:class steam, match:title ^Friends List$"
    ];
  };
}
