{
  imports = [
    ./themes/pink.nix
  ];
  programs.hyprpanel = {
    enable = true;

    # Use overlay from flake.nix
    overlay.enable = true;

    # Fix the overwrite issue with HyprPanel.
    # See below for more information.
    # Default: false
    overwrite.enable = true;

    settings = {
      theme.font.name = "GeistMono Nerd Font Propo";
      notifications.active_monitor = true;
      wallpaper.enable = false;
      scalingPriority = "hyprland";

      bar = {
        customModules = {
          microphone = {
            label = true;
          };
          hypridle = {
            offIcon = "󰒲";
            onIcon = "󰒳";
          };
        };
        # Dashboard
        launcher = {
          autoDetectIcon = false;
          icon = "󱋆";
          rightClick = "hyprpanel toggleWindow settings-dialog";
        };
        workspaces = {
          show_icons = false;
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
          # name = "GeistMono Nerd Font Propo";
          size = "14px";
        };
        osd = {
          orientation = "horizontal";
          location = "bottom";
        };
      };
    };
  };
}
