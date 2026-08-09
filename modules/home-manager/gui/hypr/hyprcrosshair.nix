{ lib, config, pkgs, ... }:

let
  cfg = config.my.hypr.crosshair;
  hyprCfg = config.my.hypr;

  # Written by hypr-swap-monitors and workspaces.nix; holds whichever monitor is
  # currently acting as primary. Same state file gpu-recorder resolves against.
  primaryMonitorFile = "${config.home.homeDirectory}/.local/state/hypr-primary-monitor";

  # Build-time value baked into profiles.ini. Only used when runtime resolution
  # fails (no state file yet, crosshair started outside a Hyprland session).
  fallbackMonitor = if cfg.monitor == "primary" then hyprCfg.monitors.primary else cfg.monitor;

  # Prints the monitor the crosshair belongs on, resolved at call time.
  monitorResolver = pkgs.writeShellApplication {
    name = "hypr-crosshair-monitor";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      configured_monitor=${lib.escapeShellArg cfg.monitor}
      state_file=${lib.escapeShellArg primaryMonitorFile}
      fallback_primary=${lib.escapeShellArg hyprCfg.monitors.primary}

      if [[ "$configured_monitor" != "primary" ]]; then
        printf '%s\n' "$configured_monitor"
        exit 0
      fi

      if [[ -s "$state_file" ]]; then
        IFS= read -r primary_monitor < "$state_file" || true
        if [[ -n "$primary_monitor" ]]; then
          printf '%s\n' "$primary_monitor"
          exit 0
        fi
      fi

      printf '%s\n' "$fallback_primary"
    '';
  };

  # Rewrites output_name in the mutable config.ini. hyprcrosshair only reads its
  # config at startup, so --restart is how a change actually takes effect.
  monitorApplier = pkgs.writeShellApplication {
    name = "hyprcrosshair-apply-monitor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.procps
      monitorResolver
      config.programs.hyprcrosshair.package
    ];
    text = ''
      config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/hyprcrosshair/config.ini"
      [[ -f "$config_file" ]] || exit 0

      monitor=$(hypr-crosshair-monitor)
      [[ -n "$monitor" ]] || exit 0

      if grep -q '^output_name=' "$config_file"; then
        sed -i "s|^output_name=.*|output_name=$monitor|" "$config_file"
      else
        printf 'output_name=%s\n' "$monitor" >> "$config_file"
      fi

      if [[ "''${1:-}" == "--restart" ]] && pgrep -x hyprcrosshair >/dev/null 2>&1; then
        pkill -x hyprcrosshair || true
        hyprcrosshair &
      fi
    '';
  };

  # Toggle resolves the monitor before launching so a start after a swap lands
  # on the right screen without waiting for the next swap.
  toggleScript = pkgs.writeShellApplication {
    name = "hyprcrosshair-toggle";
    runtimeInputs = [
      pkgs.procps
      monitorApplier
      config.programs.hyprcrosshair.package
    ];
    text = ''
      if pgrep -x hyprcrosshair >/dev/null 2>&1; then
        pkill -x hyprcrosshair || true
        exit 0
      fi

      hyprcrosshair-apply-monitor
      hyprcrosshair &
    '';
  };

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
      default = "primary";
      example = "DP-2";
      description = ''
        Monitor the crosshair renders on. A literal name (e.g. "DP-2") pins it to
        that output. The sentinel "primary" tracks whichever monitor is currently
        primary, so the crosshair follows hypr-swap-monitors.
      '';
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
    home.packages = [
      monitorResolver
      monitorApplier
      toggleScript
    ];

    programs.hyprcrosshair = {
      enable = true;
      # Re-resolve on every profile cycle so cycling never reverts the monitor
      # to the value baked into profiles.ini.
      outputNameCommand = lib.getExe monitorResolver;
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
              outputName = fallbackMonitor;
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
              outputName = fallbackMonitor;
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
              outputName = fallbackMonitor;
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
      # Toggle: kill if running, else resolve the monitor and start
      + ''
        hl.bind(${keyExpr cfg.toggleKeybind}, hl.dsp.exec_cmd("hyprcrosshair-toggle"), { locked = true })
      '';
  };
}
