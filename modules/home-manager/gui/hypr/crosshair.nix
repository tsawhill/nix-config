{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.hypr.crosshair;
  hyprCfg = config.my.hypr;
  tcross = config.programs.tcross.package;

  # Written by hypr-swap-monitors and workspaces.nix; holds whichever monitor is
  # currently acting as primary. Same state file gpu-recorder resolves against.
  primaryMonitorFile = "${config.home.homeDirectory}/.local/state/hypr-primary-monitor";

  # Build-time output in the tcross config. Only used when runtime resolution
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

  # Starts the overlay on first use. Resolves the monitor every time so a toggle
  # after a swap lands on the right screen.
  toggleScript = pkgs.writeShellApplication {
    name = "crosshair-toggle";
    runtimeInputs = [
      monitorResolver
      tcross
    ];
    text = ''
      monitor=$(hypr-crosshair-monitor)
      if [[ -n "$monitor" ]]; then
        exec tcross toggle --output "$monitor"
      fi
      exec tcross toggle
    '';
  };

  # Centres the crosshair on the pixel games treat as the middle, half a pixel
  # down-right of the exact screen centre.
  halfPixel = {
    x = 0.5;
    y = 0.5;
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
  imports = [ inputs.tcross.homeManagerModules.default ];

  options.my.hypr.crosshair = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.wayland.windowManager.hyprland.enable;
      description = "Enable the tCross crosshair overlay for Hyprland.";
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
      description = "Hyprland keybind to toggle the crosshair on/off.";
    };

  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      monitorResolver
      toggleScript
    ];

    programs.tcross = {
      enable = true;
      # Empty means no fixed primary; let Hyprland place it.
      output = if fallbackMonitor == "" then null else fallbackMonitor;
      offset = halfPixel;
      profiles = [
        # {
        #   name = "White Ring";
        #   shape = "ring";
        #   ring = {
        #     size = 6.0;
        #     thickness = 1.2;
        #   };
        #   outline.enable = true;
        # }
        {
          name = "Cyan Dot";
          shape = "dot";
          color = "#6bdfff";
          dot.size = 3.0;
          outline = {
            enable = true;
            feather = 1.0;
          };
        }
        {
          name = "Yellow Cross";
          shape = "cross";
          color = "#ffff00";
          cross = {
            thickness = 2.5;
            length = 9.0;
            gap = 5.0;
          };
          outline.enable = true;
        }
        {
          name = "Cyan Diamond";
          shape = "diamond";
          diamond.size = 3.0;
          color = "#6bdfff";
          outline = {
            enable = true;
            feather = 1.0;
          };
        }
      ];
    };

    # Locked binds (hl.bind ... { locked = true }) so they work in-game
    wayland.windowManager.hyprland.extraConfig = ''
      hl.bind(${keyExpr cfg.cycleKeybind}, hl.dsp.exec_cmd("${lib.getExe tcross} next --notify"), { locked = true })
      hl.bind(${keyExpr cfg.toggleKeybind}, hl.dsp.exec_cmd("${lib.getExe toggleScript}"), { locked = true })
    '';
  };
}
