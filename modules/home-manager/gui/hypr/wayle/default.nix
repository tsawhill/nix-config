{ lib, config, ... }:
let
  cfg = config.my.hypr;

  desktopLayout = {
    monitor = "*";
    left = [
      "hyprland-workspaces"
      "media"
    ];
    center = [ "window-title" ];
    right = [
      "volume"
      "microphone"
      "network"
      "bluetooth"
      "systray"
      "clock"
      "notifications"
      "dashboard"
    ];
  };

  laptopLayout = {
    monitor = "*";
    left = [
      "hyprland-workspaces"
      "media"
      "systray"
      "idle-inhibit"
    ];
    center = [ "window-title" ];
    right = [
      "volume"
      "microphone"
      "network"
      "bluetooth"
      "battery"
      "clock"
      "notifications"
      "dashboard"
    ];
  };
in
{
  imports = [
    ./themes/pink.nix
  ];

  options.my.hypr.panel.theme = lib.mkOption {
    type = lib.types.str;
    default = "pink";
    description = "Wayle theme to apply. Add a corresponding file in themes/ and guard it with lib.mkIf.";
  };

  config.services.wayle = {
    enable = true;
    settings = {
      bar = {
        layout = [
          (if cfg.layout == "desktop" then desktopLayout else laptopLayout)
        ];
        location = "top";
        inset-edge = 0.6;
        inset-ends = 0;
        background-opacity = 0;
        button-variant = "block-prefix";
        button-bg-opacity = 80;
        button-label-weight = "bold";
        button-rounding = "sm";
        button-border-location = "all";
      };

      general = {
        font-sans = "DaddyTimeMono Nerd Font";
        font-mono = "DaddyTimeMono Nerd Font";
        tearing-mode = true;
      };

      modules = {
        hyprland-workspaces = {
          min-workspace-count = 0;
          monitor-specific = true;
          show-special = false;
          display-mode = "label";
          app-icons-show = false;
          active-indicator = "background";
        };

        window-title = {
          format = "{{ title }}";
          icon-show = true;
          label-show = true;
          label-max-length = 50;
        };

        media = {
          icon-show = true;
          label-show = true;
          label-max-length = 35;
        };

        volume = {
          label-show = true;
          right-click = "if pgrep pavucontrol > /dev/null; then pkill -9 pavucontrol; else pavucontrol; fi";
          scroll-down = "wayle audio output-volume -3";
          scroll-up = "wayle audio output-volume +3";
        };

        microphone.label-show = true;

        bluetooth = {
          label-show = true;
          right-click = "if pgrep 'blueman-manager*' > /dev/null; then pkill -9 'blueman-manager*'; else blueman-manager; fi";
        };

        network = {
          label-show = true;
          right-click = "if pgrep 'nm-connection*' > /dev/null; then pkill -9 'nm-connection*'; else nm-connection-editor; fi";
        };

        clock = {
          format = "%a %b %d  %I:%M %p";
          icon-show = true;
          label-show = true;
        };

        idle-inhibit = {
          icon-inactive = "tb-coffee-off-symbolic";
          icon-active = "tb-coffee-symbolic";
          label-show = false;
        };

        notifications.popup-monitor = "primary";
      };

      osd = {
        enabled = true;
        position = "bottom";
        monitor = "primary";
      };

      # Wallpaper Engine is managed separately by wallpaper-engine.nix.
      wallpaper.engine-enabled = false;
    };
  };
}
