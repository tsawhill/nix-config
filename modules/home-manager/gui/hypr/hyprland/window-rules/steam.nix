{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.python-xlib ]);
  toastPositioner = pkgs.writeShellScript "steam-toast-positioner" ''
    export PATH=${
      lib.makeBinPath [
        config.wayland.windowManager.hyprland.package
        pkgs.xrandr
      ]
    }:$PATH
    exec ${python}/bin/python ${./steam-toasts.py}
  '';
  session = "wayland-session@hyprland.desktop.target";
in
{
  options.my.hypr.windowRules.steam.enable = lib.mkEnableOption "steam window rules" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.windowRules.steam.enable {
    # Steam's override-redirect toasts bypass compositor placement rules.
    systemd.user.services.steam-toast-positioner = {
      Unit = {
        Description = "Keep Steam desktop toasts clear of reserved bar space";
        After = [ session ];
        PartOf = [ session ];
      };
      Service = {
        ExecStart = "${toastPositioner}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ session ];
    };
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
