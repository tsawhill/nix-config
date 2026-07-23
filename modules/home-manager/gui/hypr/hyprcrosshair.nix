{ lib, config, ... }:

let
  cfg = config.my.hypr.crosshair;
  hyprCfg = config.my.hypr;

  # Translate a hyprlang bind prefix ("$mainMod SHIFT, Key") into a Lua key
  # expression for hl.bind, referencing the `mainMod` local from default.nix.
  keyExpr =
    spec:
    let
      toks = lib.filter (t: t != "") (lib.splitString " " (lib.replaceStrings [ "," ] [ " " ] spec));
      key = lib.last toks;
      mods = lib.init toks;
      otherMods = lib.filter (t: t != "$mainMod") mods;
      suffix = lib.concatStringsSep " + " (otherMods ++ [ key ]);
    in
    if lib.elem "$mainMod" mods then ''mainMod .. " + ${suffix}"'' else ''"${suffix}"'';
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
          # {
          #   name = "White Ring";
          #   settings = {
          #     outputName = cfg.monitor;
          #     shape = "ring";
          #     color = {
          #       red = 1.0;
          #       green = 1.0;
          #       blue = 1.0;
          #     };
          #     ring.size = 6.0;
          #     ring.thickness = 1.2;
          #     outline = {
          #       enable = true;
          #       size = 1.0;
          #       feather = 0.0;
          #     };
          #   };
          # }
          {
            name = "Yellow Dot";
            settings = {
              outputName = cfg.monitor;
              shape = "dot";
              color = {
                red = 1.0;
                green = 1.0;
                blue = 0.0;
              };
              dot.size = 2.5;
              outline = {
                enable = true;
                size = 1.2;
                feather = 1.0;
              };
            };
          }
          {
            name = "Yellow Cross";
            settings = {
              outputName = cfg.monitor;
              shape = "cross";
              color = {
                red = 1.0;
                green = 1.0;
                blue = 0.0;
              };
              cross.thickness = 2.5;
              cross.length = 9.0;
              cross.gap = 5.0;
              outline = {
                enable = true;
                size = 1.0;
                feather = 0.0;
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
                blue = 1.0;
                alpha = 1.0;
              };
              cross.thickness = 1.7;
              cross.length = 3.0;
              chevron.angle = 45.0;
              outline = {
                enable = true;
                size = 1.0;
                feather = 0.0;
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

    # Locked binds (hl.bind ... { locked = true }) so they work in-game
    wayland.windowManager.hyprland.extraConfig =
      lib.optionalString (config.programs.hyprcrosshair.profiles.configs != [ ]) ''
        hl.bind(${keyExpr cfg.cycleKeybind}, hl.dsp.exec_cmd("hyprcrosshair-cycle"), { locked = true })
      ''
      # Toggle: kill if running, start if not
      + ''
        hl.bind(${keyExpr cfg.toggleKeybind}, hl.dsp.exec_cmd("pkill -x hyprcrosshair || hyprcrosshair"), { locked = true })
      '';
  };
}
