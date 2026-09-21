{ lib, config, ... }:
let
  cfg = config.my.desktop.audio.lowLatency;
  latency = "${toString cfg.quantum}/${toString cfg.rate}";
  maxLatency = "${toString cfg.maxQuantum}/${toString cfg.rate}";
  alsaHeadroom = if cfg.alsaHeadroom == null then cfg.quantum * 2 else cfg.alsaHeadroom;
  forceQuantumProps = {
    "node.force-quantum" = cfg.quantum;
    "node.force-rate" = cfg.rate;
  };
  forceQuantumRule = {
    matches = [ { "node.name" = "~.*"; } ];
    actions.update-props = forceQuantumProps;
  };
  mkPulseCaptureRule =
    binary: quantum:
    let
      captureLatency = "${toString quantum}/${toString cfg.rate}";
    in
    {
      matches = [
        {
          "application.process.binary" = binary;
        }
      ];
      actions.update-props = {
        "pulse.min.frag" = captureLatency;
        "pulse.default.frag" = captureLatency;
        "pulse.min.quantum" = captureLatency;
      };
    };
in
{
  options.my.desktop.audio.lowLatency = {
    enable = lib.mkEnableOption "low-latency PipeWire tuning";

    quantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 128;
      description = "PipeWire default buffer size in samples. Lower = less latency, higher xrun risk.";
    };

    rate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48000;
      description = "PipeWire default sample rate in Hz.";
    };

    maxQuantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 512;
      description = "Largest default PipeWire quantum allowed for the low-latency profile.";
    };

    alsaHeadroom = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "Extra ALSA buffering headroom in samples. Zero minimizes latency; null defaults to twice the configured quantum.";
    };

    forceStreams = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force every PipeWire and PulseAudio-compatible stream to the configured quantum.";
    };

    pulseCaptureQuantumByProcess = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      example.gpu-screen-recorder = 512;
      description = "Minimum capture quantum, in samples, for matching PulseAudio client process binaries.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.maxQuantum >= cfg.quantum;
        message = "my.desktop.audio.lowLatency.maxQuantum must be greater than or equal to quantum.";
      }
    ];

    services.pipewire = {
      extraConfig.pipewire."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = cfg.rate;
          "default.clock.quantum" = cfg.quantum;
          "default.clock.max-quantum" = cfg.maxQuantum;
        };
      }
      // lib.optionalAttrs cfg.forceStreams {
        "stream.rules" = [ forceQuantumRule ];
      };

      extraConfig.pipewire-pulse."92-low-latency" = {
        "pulse.properties" = {
          "pulse.min.req" = latency;
          "pulse.default.req" = latency;
          "pulse.default.tlength" = maxLatency;
          "pulse.min.frag" = latency;
          "pulse.default.frag" = latency;
          "pulse.min.quantum" = latency;
        };
        # Pulse rules match client properties, not stream media classes.
        "pulse.rules" = lib.mapAttrsToList mkPulseCaptureRule cfg.pulseCaptureQuantumByProcess;
        "stream.rules" = lib.optionals cfg.forceStreams [ forceQuantumRule ];
      };

      extraConfig.client."92-low-latency" = lib.mkIf cfg.forceStreams {
        "stream.rules" = [ forceQuantumRule ];
      };

      # Let ALSA choose the period count; unrelated devices may suspend normally.
      wireplumber.extraConfig."13-low-latency"."monitor.alsa.rules" = [
        {
          matches = [ { "node.name" = "~alsa_.*"; } ];
          actions.update-props = {
            "api.alsa.period-size" = cfg.quantum;
            "api.alsa.headroom" = alsaHeadroom;
          };
        }
      ];
    };
  };
}
