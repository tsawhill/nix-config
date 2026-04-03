{ lib, config, ... }:
let
  cfg = config.my.desktop.audio.mics;
in
{
  options.my.desktop.audio.mics = {
    virtual.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable virtual mic input sink as the default audio input for all applications. Physical input devices auto-connect to it.";
    };
  };

  config = lib.mkIf cfg.virtual.enable {
    services.pipewire = {

      # Virtual mic loopback:
      #   capture side  – passive; WirePlumber auto-connects it to the highest-priority
      #                   source (presonus_mic_processed at 2150 > physical USB at 2109)
      #   playback side – exposed as Audio/Source/Virtual at priority 2200, so apps
      #                   using either native PW or PulseAudio compat default to it
      extraConfig.pipewire."93-virtual-mic"."context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Mic Input";
            "capture.props" = {
              "node.name"        = "mic_input_capture";
              "node.description" = "Mic Input Capture";
              "audio.position"   = [ "FL" "FR" ];
              # Explicitly target the DSP chain output rather than letting WirePlumber
              # pick (it ignores priority.session for virtual vs physical sources).
              # Not passive — the loopback must always be connected so mic_input
              # is live for any app that opens it.
              "target.object"    = "presonus_mic_processed";
            };
            "playback.props" = {
              "node.name"        = "mic_input";
              "node.description" = "Mic Input";
              "media.class"      = "Audio/Source/Virtual";
              "audio.position"   = [ "FL" "FR" ];
              # Beat the physical USB mic (2109) and presonus_mic_processed (2150)
              # so apps default here without needing explicit routing rules.
              "priority.session" = 2200;
            };
          };
        }
      ];

      # Force PulseAudio-compat input streams to mic_input.
      # NOTE: pipewire-pulse rules only affect PulseAudio clients — native PipeWire
      # nodes like mic_input_capture are unaffected, so there is no routing loop.
      extraConfig.pipewire-pulse."94-mic-input-routing"."stream.rules" = [
        {
          matches = [ { "media.class" = "Stream/Input/Audio"; } ];
          actions.update-props."node.target" = "mic_input";
        }
      ];
    };
  };
}
