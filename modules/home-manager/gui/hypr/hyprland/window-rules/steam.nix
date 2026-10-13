{ config, lib, ... }:
{
  options.my.hypr.windowRules.steam.enable = lib.mkEnableOption "steam window rules" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.windowRules.steam.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # Suppress steam from stealing focus
      {
        match = {
          class = "steam";
        };
        suppress_event = "activatefocus";
        no_initial_focus = true;
      }

      # Block idle inhibition and focus grabs from notification toasts.
      {
        match = {
          class = "steam";
          title = "notificationtoasts.*";
        };
        idle_inhibit = "none";
        suppress_event = "activatefocus";
        no_initial_focus = true;
      }

      # Only reposition new toasts on workspaces without a fullscreen window.
      # Leave 80 logical pixels for the bottom Wayle bar and its inset;
      # fullscreen games keep Steam's own toast placement.
      {
        match = {
          class = "steam";
          title = "notificationtoasts.*";
          workspace = "f[-1]";
        };
        float = true;
        move = "(monitor_w-window_w-15) (monitor_h-window_h-80)";
      }

      # Float titled windows (untitled ones are menus) at the chat spot, top right.
      # Sizes are monitor fractions; rules take muParser expressions, not "%".
      {
        match = {
          class = "steam";
          title = "negative:(|notificationtoasts.*)";
        };
        float = true;
        move = "(monitor_w*0.612) (monitor_h*0.04)";
        size = "(monitor_w*0.286) (monitor_h*0.43)";
      }

      # Library lower left; width stays above Steam's 1515px minimum on 2560.
      {
        match = {
          class = "steam";
          title = "Steam";
        };
        move = "15 (monitor_h*0.28)";
        size = "(monitor_w*0.595) (monitor_h*0.66)";
      }

      # Friends list lower right, flush with the screen edge margin.
      {
        match = {
          class = "steam";
          title = "Friends List";
        };
        move = "(monitor_w*0.785-15) (monitor_h*0.49)";
        size = "(monitor_w*0.215) (monitor_h*0.51-15)";
      }
    ];
  };
}
