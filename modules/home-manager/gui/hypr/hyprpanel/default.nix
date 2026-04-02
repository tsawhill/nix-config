{ lib, config, ... }:
let
  cfg = config.my.hypr;

  desktopLayout = {
    "*" = {
      left = [ "workspaces" "media" ];
      middle = [ "windowtitle" ];
      right = [ "volume" "microphone" "network" "bluetooth" "systray" "clock" "notifications" "dashboard" ];
    };
  };

  laptopLayout = {
    "*" = {
      left = [ "workspaces" "media" "systray" "hypridle" ];
      middle = [ "windowtitle" ];
      right = [ "volume" "microphone" "network" "bluetooth" "battery" "clock" "notifications" "dashboard" ];
    };
  };
in
{
  imports = [
    ./themes/pink.nix
  ];

  options.my.hypr.panel.theme = lib.mkOption {
    type = lib.types.str;
    default = "pink";
    description = "HyprPanel theme to apply. Add a corresponding file in themes/ and guard it with lib.mkIf.";
  };

  config = {
    programs.hyprpanel = {
      enable = true;
      settings = {
        "bar.layouts" = if cfg.layout == "desktop" then desktopLayout else laptopLayout;

        notifications.active_monitor = true;
        wallpaper.enable = false;
        scalingPriority = "hyprland";
        tear = true;

        bar = {
          general = {
            margin_bottom = "0.6em";
            margin_top = "0em";
            vertical_margins = "0em";
          };
          customModules = {
            microphone.label = true;
            hypridle = {
              offIcon = "󰒲";
              onIcon = "󰒳";
            };
          };
          launcher = {
            autoDetectIcon = false;
            icon = "󱋆";
            rightClick = "hyprpanel toggleWindow settings-dialog";
          };
          workspaces = {
            show_icons = false;
            workspaces = 0;
            show_numbered = false;
            showApplicationIcons = false;
            showWsIcons = false;
            workspaceMask = false;
          };
          windowtitle = {
            class_name = false;
            custom_title = false;
            icon = true;
            label = true;
          };
          media = {
            show_active_only = true;
            show_label = true;
            truncation = true;
          };
          volume = {
            label = true;
            rightClick = "if pgrep \"pavucontrol\" > /dev/null; then pkill -9 \"pavucontrol\"; else pavucontrol; fi";
            scrollDown = "hyprpanel vol -3";
            scrollUp = "hyprpanel vol +3";
          };
          bluetooth = {
            label = true;
            rightClick = "if pgrep \"blueman-manager*\" > /dev/null; then pkill -9 \"blueman-manager*\"; else blueman-manager; fi";
          };
          network = {
            label = true;
            rightClick = "if pgrep \"nm-connection*\" > /dev/null; then pkill -9 \"nm-connection*\"; else nm-connection-editor; fi";
            showWifiInfo = true;
          };
          clock = {
            format = "%a %b %d  %I:%M %p";
            showIcon = true;
            showTime = true;
          };
        };

        menus = {
          clock = {
            time = {
              hideSeconds = false;
              military = true;
            };
            weather.enabled = false;
          };
          dashboard = {
            directories.enabled = false;
            shortcuts.enabled = false;
            powermenu.avatar.image = "/home/taylor/.face.icon";
          };
        };

        theme = {
          font = {
            name = "DaddyTimeMono Nerd Font";
            size = "1rem";
            weight = 700;
          };
          osd = {
            orientation = "horizontal";
            location = "bottom";
          };
        };
      };
    };
  };
}
