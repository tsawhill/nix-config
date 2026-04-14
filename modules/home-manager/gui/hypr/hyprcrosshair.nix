{ lib, config, ... }:

let
  cfg = config.my.hypr.crosshair;
  hyprCfg = config.my.hypr;
in
{
  options.my.hypr.crosshair = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.wayland.windowManager.hyprland.enable;
      description = "Enable hyprcrosshair overlay for Hyprland.";
    };

    monitor = lib.mkOption {
      type = lib.types.str;
      default = hyprCfg.monitors.primary or "";
      description = "Monitor name for crosshair (defaults to primary monitor).";
    };

    cycleKeybind = lib.mkOption {
      type = lib.types.str;
      default = "$mainMod, C";
      description = "Hyprland keybind for cycling crosshair profiles.";
    };

    toggleKeybind = lib.mkOption {
      type = lib.types.str;
      default = "$mainMod SHIFT, C";
      description = "Hyprland keybind to toggle hyprcrosshair on/off.";
    };

  };

  config = lib.mkIf cfg.enable {
    programs.hyprcrosshair = {
      enable = true;
      profiles = {
        active = 0;
        configs = [
          {
            name = "White Ring";
            settings = {
              outputName = cfg.monitor;
              shape = "ring";
              color = {
                red = 1.0;
                green = 1.0;
                blue = 1.0;
              };
              ring.size = 6.0;
              ring.thickness = 1.2;
              outline = {
                enable = true;
                size = 1.0;
                feather = 0.0;
              };
            };
          }
          {
            name = "Cyan Dot";
            settings = {
              outputName = cfg.monitor;
              shape = "dot";
              color = {
                red = 0.0;
                green = 1.0;
                blue = 1.0;
              };
              dot.size = 2.5;
              outline = {
                enable = true;
                size = 0.1;
                feather = 1.3;
              };
            };
          }
          {
            name = "Chevron";
            settings = {
              outputName = "DP-4";
              shape = "chevron";
              dot.size = 2.0;
              color = {
                red = 1.0;
                green = 1.0;
                blue = 0.75;
                alpha = 1.0;
              };
              cross.thickness = 1.9;
              cross.length = 5.0;
              chevron.angle = 44.0;
              outline = {
                enable = true;
                size = 1.0;
                feather = 0.15;
                color = {
                  red = 0.0;
                  green = 0.0;
                  blue = 0.0;
                };
              };
            };
          }
        ];
      };
    };

    # Locked binds so they work in-game
    wayland.windowManager.hyprland.settings.bindl =
      lib.optionals (config.programs.hyprcrosshair.profiles.configs != [ ]) [
        "${cfg.cycleKeybind}, exec, hyprcrosshair-cycle"
      ]
      ++ [
        # Toggle: kill if running, start if not
        "${cfg.toggleKeybind}, exec, pkill -x hyprcrosshair || hyprcrosshair"
      ];
  };
}
