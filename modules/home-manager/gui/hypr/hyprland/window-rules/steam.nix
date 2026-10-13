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
          title = "notificationtoasts.*";
        };
        idle_inhibit = "none";
        suppress_event = "activatefocus";
        no_initial_focus = true;
      }
    ];

    # Library, friends and chats tile on their own; menus stay floating.
    wayland.windowManager.hyprland.extraConfig = ''
      dofile("${./workspace-layouts.lua}").steam()
    '';
  };
}
