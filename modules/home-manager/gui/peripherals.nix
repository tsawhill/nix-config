{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.peripherals;
  m7 = cfg.mchose-m7-ultra;
  inherit (lib) mkOption types;

  settings = (pkgs.formats.json { }).generate "periph.json" {
    inherit (cfg) dryRun;
    mchoseM7Ultra =
      if m7.enable then
        {
          inherit (m7)
            dpiStages
            activeStage
            pollingRate
            liftOff
            ripple
            angleSnap
            motionSync
            angleCorrection
            performanceMode
            debounceMs
            sleepMinutes
            lighting
            buttons
            ;
        }
      else
        null;
  };

  # Fails the deploy on anything the daemon would reject.
  checked = pkgs.runCommand "periph.json" { } ''
    ${lib.getExe cfg.package} check --config ${settings}
    cp ${settings} $out
  '';

  bool =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };
  rate =
    description:
    mkOption {
      type = types.enum [
        125
        500
        1000
        2000
        4000
        8000
      ];
      default = 1000;
      inherit description;
    };
in
{
  options.my.peripherals = {
    enable = lib.mkEnableOption "applying declared mouse and keyboard settings whenever a device connects";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../../pkgs/periph { };
      description = "The periph package.";
    };

    dryRun = bool true "Log what would change without writing to any device.";

    # Defaults are the factory values from MCHOSE's driver, so anything unset is reset to factory.
    mchose-m7-ultra = {
      enable = bool true "Enforce these settings on the MCHOSE M7 Ultra.";
      dpiStages = mkOption {
        type = types.addCheck (types.listOf (types.ints.between 50 42000)) (
          l: l != [ ] && builtins.length l <= 6
        );
        default = [
          400
          800
          1600
          3200
          6400
          42000
        ];
        description = "DPI values the DPI button cycles through, 1 to 6 of them.";
      };
      activeStage = mkOption {
        type = types.ints.between 1 6;
        default = lib.min 3 (builtins.length m7.dpiStages);
        defaultText = lib.literalExpression "min 3 (length dpiStages)";
        description = "Active DPI stage, counting from 1.";
      };
      pollingRate.wired = rate "Polling rate over the cable, in Hz.";
      pollingRate.wireless = rate "Polling rate over the 2.4 GHz dongle, in Hz.";
      liftOff = mkOption {
        type = types.enum [
          "0.7mm"
          "1mm"
          "2mm"
        ];
        default = "0.7mm";
        description = "Lift-off distance.";
      };
      ripple = bool false "Ripple control: smoothing for sensor jitter at high DPI.";
      angleSnap = bool false "Angle snapping: straightens near-straight movements.";
      motionSync = bool false "Motion sync: aligns sensor reads with the polling clock.";
      angleCorrection = mkOption {
        type = types.ints.between (-30) 30;
        default = 0;
        description = "Sensor angle correction in degrees, with the sign M HUB shows.";
      };
      performanceMode = mkOption {
        type = types.enum [
          "performance"
          "gaming"
          "extreme"
        ];
        default = "performance";
        description = "Sensor and controller power mode; faster modes use more battery.";
      };
      debounceMs = mkOption {
        type = types.ints.u8;
        default = 8;
        description = "Click debounce in milliseconds.";
      };
      sleepMinutes = mkOption {
        type = types.ints.u8;
        default = 3;
        description = "Idle minutes before the mouse sleeps; 0 never sleeps.";
      };
      lighting = bool true "Mouse lighting on or off.";
      buttons.dpi = mkOption {
        type = types.enum [
          "default"
          "disabled"
        ];
        default = "default";
        description = "The bottom DPI button.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.periphd = {
      Unit.Description = "Apply declared mouse and keyboard settings";
      Service = {
        ExecStart = "${lib.getExe cfg.package} daemon --config ${checked}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
