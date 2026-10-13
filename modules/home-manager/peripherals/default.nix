{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.peripherals;
  m7 = cfg.mchose-m7-ultra;
  kb = cfg.boyi-h60pro;
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
    boyiH60pro =
      if kb.enable then
        {
          inherit (kb)
            dryRun
            pollingRate
            debounceMs
            lighting
            fnLayer
            antiMistouch
            rtStabilityMs
            wasdSwap
            actuation
            release
            keys
            rapidTrigger
            bottomDeadzone
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
  # null leaves the keyboard's current value.
  maybe =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
  travel = min: max: types.numbers.between min max;
in
{
  # Device modules next to this one (mchose-m7-ultra.nix, ...) turn a device on with
  # personal defaults; everything here defaults to off and factory values.
  options.my.peripherals = {
    enable = mkOption {
      type = types.bool;
      default = m7.enable || kb.enable;
      defaultText = lib.literalExpression "any device enabled";
      description = "Run the service that applies device settings whenever a device connects.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../../pkgs/periph { };
      description = "The periph package.";
    };

    dryRun = bool true "Log what would change without writing to any device.";

    # Defaults are the factory values from MCHOSE's driver, so anything unset is reset to factory.
    mchose-m7-ultra = {
      enable = bool false "Enforce these settings on the MCHOSE M7 Ultra.";
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

    # Defaults are factory values where known; polling rate, debounce, lighting and the
    # rapid trigger sensitivities aren't, so they default to null (left as the board has them).
    boyi-h60pro = {
      enable = bool false "Enforce these settings on the BOYI H60Pro.";
      dryRun = mkOption {
        type = types.bool;
        default = cfg.dryRun;
        defaultText = lib.literalExpression "config.my.peripherals.dryRun";
        description = "Only log what would change on this keyboard.";
      };
      pollingRate = maybe (types.enum [
        125
        250
        500
        1000
        2000
        4000
        8000
      ]) "Polling rate in Hz.";
      debounceMs = maybe (types.ints.between 0 50) "Key debounce in milliseconds.";
      lighting = {
        effect = maybe types.str "Lighting effect name, as `periph show` prints it.";
        brightness = maybe (types.ints.between 0 4) "Lighting brightness, 0-4.";
        speed = maybe (types.ints.between 0 4) "Effect speed, 0 (slow) to 4 (fast).";
        color = maybe (types.strMatching "#[0-9a-fA-F]{6}") "Effect colour as #rrggbb.";
        rainbow = maybe types.bool "Cycle rainbow colours instead of one colour.";
      };
      fnLayer = maybe (types.ints.between 0 1) "Which of the two Fn layouts is active." // {
        default = 0;
      };
      antiMistouch = maybe types.bool "The vendor's anti-mistouch toggle." // {
        default = false;
      };
      rtStabilityMs =
        maybe (types.enum [
          0
          25
          50
          75
          100
          125
        ]) "Rapid trigger chatter filter in milliseconds."
        // {
          default = 0;
        };
      wasdSwap = bool false "Swap WASD and the arrow keys (the Fn+W toggle).";
      actuation = mkOption {
        type = travel 0.1 3.3;
        default = 2.0;
        description = "Actuation point in mm, for every key.";
      };
      release = maybe (travel 0.1 3.3) "Release point in mm; null matches the actuation point.";
      keys = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              actuation = maybe (travel 0.1 3.3) "This key's actuation point in mm.";
              release = maybe (travel 0.1 3.3) "This key's release point in mm.";
            };
          }
        );
        default = { };
        example = lib.literalExpression "{ W.actuation = 0.5; }";
        description = "Per-key overrides by key name, as the database names them (W, Space, LShift, ...).";
      };
      rapidTrigger = {
        enable = bool false "Rapid trigger on every key.";
        press = maybe (travel 0.01 2.0) "Rapid trigger press sensitivity in mm.";
        release = maybe (travel 0.01 2.0) "Rapid trigger release sensitivity in mm.";
      };
      bottomDeadzone = maybe (travel 0.0 1.0) "Bottom dead zone in mm." // {
        default = 0.3;
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
