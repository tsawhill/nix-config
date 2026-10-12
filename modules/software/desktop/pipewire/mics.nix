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

      # mic_input always exists; its loopback picks a processed mic when one is
      # plugged in (higher priority) and the plain default source otherwise.
      extraConfig.pipewire."93-virtual-mic"."context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Mic Input";
            "capture.props" = {
              "node.name" = "mic_input_capture";
              "node.description" = "Mic Input Capture";
              "audio.position" = [
                "FL"
                "FR"
              ];
            };
            "playback.props" = {
              "node.name" = "mic_input";
              "node.description" = "Mic Input";
              "media.class" = "Audio/Source/Virtual";
              "audio.position" = [
                "FL"
                "FR"
              ];
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
