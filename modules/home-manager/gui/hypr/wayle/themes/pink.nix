{ config, lib, ... }:
let
  bg = "#242438";
  primary = "#c4a7e7";
  faint = "#636394";

  splitButtonTheme = {
    border-show = true;
    border-color = faint;
    icon-color = primary;
    icon-bg-color = bg;
    label-color = bg;
    button-bg-color = primary;
  };

  splitButtonModules = [
    "battery"
    "bluetooth"
    "clock"
    "idle-inhibit"
    "media"
    "network"
    "notifications"
    "volume"
    "window-title"
  ];
in
lib.mkIf (config.my.hypr.panel.theme == "pink") {
  services.wayle.settings = {
    styling = {
      theme-provider = "wayle";
      rounding = "lg";
      palette = {
        inherit bg primary;
        surface = "#2a2a40";
        elevated = "#31314a";
        fg = primary;
        fg-muted = faint;
        red = "#eb6f92";
        yellow = "#f6c177";
        green = "#9ccfd8";
        blue = "#31748f";
      };
    };

    bar = {
      bg = "transparent";
      border-color = faint;
      shadow = "none";
      button-group-background = "transparent";
      button-group-border-color = faint;
      scale = 0.9;
      inset-ends = 0.5;
      padding-ends = 1.0;
      button-icon-size = 0.85;
    };

    modules = lib.genAttrs splitButtonModules (_: splitButtonTheme) // {
      microphone = splitButtonTheme // {
        icon-color = primary;
        icon-bg-color = bg;
      };

      dashboard = {
        border-show = true;
        border-color = faint;
        icon-color = primary;
        icon-bg-color = bg;
      };

      systray = {
        border-show = true;
        border-color = faint;
        button-bg-color = primary;
      };

      hyprland-workspaces = {
        container-bg-color = bg;
        active-color = primary;
        occupied-color = primary;
        empty-color = faint;
        border-show = true;
        border-color = faint;
      };
    };
  };
}
