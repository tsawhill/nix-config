{ lib, config, ... }:
let
  cfg = config.my.hypr.idle;
  enabled = t: t > 0;
  toSec = m: m * 60;
in
{
  options.my.hypr.idle = {
    screenOff.time = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Minutes before screen off. 0 or -1 to disable.";
    };
    lock.time = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Minutes before lock. 0 or -1 to disable.";
    };
    sleep.time = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Minutes before sleep. 0 or -1 to disable.";
    };
  };

  config = {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "hyprlock";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };
        listener = lib.filter (x: x != null) [
          (if enabled cfg.screenOff.time then {
            timeout = toSec cfg.screenOff.time;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          } else null)
          (if enabled cfg.lock.time then {
            timeout = toSec cfg.lock.time;
            on-timeout = "hyprlock";
          } else null)
          (if enabled cfg.sleep.time then {
            timeout = toSec cfg.sleep.time;
            on-timeout = "systemctl suspend";
          } else null)
        ];
      };
    };

    # Scope the home-manager generated service to the Hyprland session only
    systemd.user.services.hypridle = {
      Unit = {
        After = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
        PartOf = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
      };
      Install.WantedBy = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
    };
  };
}
