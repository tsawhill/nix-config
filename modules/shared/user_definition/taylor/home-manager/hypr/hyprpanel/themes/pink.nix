{ config, lib, ... }:
{
  options = {
    hyprpanelPink.background = lib.mkOption {
      type = lib.types.str;
      default = "#242438";
    };
    hyprpanelPink.pink_primary = lib.mkOption {
      type = lib.types.str;
      default = "#c4a7e7";
    };
    hyprpanelPink.faint_background = lib.mkOption {
      type = lib.types.str;
      default = "#636394";
    };
  };

  config = {
    programs.hyprpanel.settings = {
      theme = {
        name = "rose_pine_split";
        bar = {
          floating = true;
          transparent = true;
          menus = {
            card_radius = "15";
            border.radius = "15";
            buttons.radius = "15";
          };
          buttons = {
            radius = "4";
            style = "split";
            monochrome = true;
            enableBorders = true;
            borderColor = config.hyprpanelPink.faint_background;
            text = config.hyprpanelPink.background;
            icon_background = config.hyprpanelPink.background;
            icon = config.hyprpanelPink.pink_primary;
            background = config.hyprpanelPink.pink_primary;
            background_opacity = "80";
            modules = {
              microphone = {
                background = config.hyprpanelPink.pink_primary;
                icon = config.hyprpanelPink.background;
                enableBorder = true;
              };
              hypridle = {
                background = config.hyprpanelPink.pink_primary;
                icon = config.hyprpanelPink.background;
              };
            };
            workspaces = {
              active = config.hyprpanelPink.background;
              occupied = config.hyprpanelPink.faint_background;
            };
          };
          menus = {
            monochrome = true;
          };
        };
      };
    };
  };
}
