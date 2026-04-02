{ lib, ... }:
# NOTE FOR DEVELOPERS:
# config.my.hypr.layout             — "desktop" | "laptop"
# config.my.hypr.monitors.primary   — primary monitor name (e.g. "DP-4"); empty = Hyprland auto
# config.my.hypr.monitors.secondary — secondary monitor name, or null for single-screen setups
# These options are declared here and consumed by submodules.
{
  imports = [
    ./input.nix
    ./autostart.nix
    ./appearance.nix
    ./bindings.nix
    ./workspaces.nix
    ./monitor-events.nix
    ./swap-monitors.nix
    ./window-rules
    ./dwindle.nix
    ./gpu-recorder.nix
    ./monitors
  ];

  options.my.hypr = {
    layout = lib.mkOption {
      type = lib.types.enum [
        "desktop"
        "laptop"
      ];
      default = "desktop";
      description = "The monitor/workspace layout profile to use.";
    };

    monitors = {
      primary = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Primary monitor name (e.g. DP-4). Empty string lets Hyprland auto-assign.";
      };
      secondary = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Secondary monitor name, or null for single-screen setups.";
      };
    };
  };

  config.wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false; # Using uwsm -- https://wiki.hyprland.org/Useful-Utilities/Systemd-start/
    settings = {
      env = [
        "GDK_SCALE, 1"
        "ELECTRON_OZONE_PLATFORM_HINT,wayland"
        "EDITOR, nvim"
      ];

      misc = {
        vfr = true;
        disable_hyprland_logo = true;
        enable_swallow = false;
        swallow_regex = "^(foot)$";
        enable_anr_dialog = false;
      };

      general = {
        layout = "dwindle";
        allow_tearing = true;
      };

      "$mainMod" = "SUPER";
    };
  };
}
