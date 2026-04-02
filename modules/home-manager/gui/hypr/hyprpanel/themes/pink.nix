{ config, lib, ... }:
let
  bg = "#242438";
  primary = "#c4a7e7";
  faint = "#636394";
in
lib.mkIf (config.my.hypr.panel.theme == "pink") {
  programs.hyprpanel.settings.theme = {
    bar = {
      floating = true;
      location = "top";
      transparent = true;
      menus = {
        card_radius = "15";
        border.radius = "15";
        buttons.radius = "15";
        monochrome = true;
      };
      buttons = {
        radius = "4";
        style = "split";
        monochrome = true;
        enableBorders = true;
        borderColor = faint;
        text = bg;
        icon_background = bg;
        icon = primary;
        background = primary;
        background_opacity = "80";
        modules = {
          microphone = {
            background = primary;
            icon = bg;
            enableBorder = true;
          };
          hypridle = {
            background = primary;
            icon = bg;
          };
        };
        workspaces = {
          active = bg;
          occupied = faint;
        };
      };
    };
  };
}
