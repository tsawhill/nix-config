{ config, lib, ... }:
let
  primary  = "ffcce6";
  accent   = "9778D0";
  bg       = "1e1e2e";
  text     = "cdd6f4";
  subtext  = "bac2de";
  fail     = "f38ba8";
  capslock = "fab387";
in
lib.mkIf (config.my.hypr.lock.theme == "pink") {
  programs.hyprlock.settings = {
    general = {
      hide_cursor = true;
    };

    background = [
      {
        monitor = "";
        path = "screenshot";
        blur_passes = 3;
        blur_size = 6;
        brightness = 0.6;
      }
    ];

    input-field = [
      {
        monitor = "";
        size = "300, 50";
        position = "0, -80";
        halign = "center";
        valign = "center";

        outline_thickness = 3;
        outer_color    = "rgba(${primary}ff)";
        inner_color    = "rgba(${bg}99)";
        font_color     = "rgba(${text}ff)";

        placeholder_text = "<i>Password...</i>";
        check_color      = "rgba(${accent}ff)";
        fail_color       = "rgba(${fail}ff)";
        fail_text        = "<i>$FAIL ($ATTEMPTS)</i>";
        capslock_color   = "rgba(${capslock}ff)";

        shadow_passes = 2;
      }
    ];

    label = [
      # Clock
      {
        monitor = "";
        text = ''cmd[update:1000] echo "$(date +"%H:%M")"'';
        font_size = 90;
        font_family = "DaddyTimeMono Nerd Font Bold";
        color = "rgba(${text}ff)";
        position = "0, 100";
        halign = "center";
        valign = "center";
        shadow_passes = 2;
        shadow_size = 4;
      }
      # Date
      {
        monitor = "";
        text = ''cmd[update:60000] echo "$(date +"%A, %B %d")"'';
        font_size = 20;
        font_family = "DaddyTimeMono Nerd Font";
        color = "rgba(${subtext}ff)";
        position = "0, 10";
        halign = "center";
        valign = "center";
        shadow_passes = 2;
        shadow_size = 4;
      }
    ];
  };
}
