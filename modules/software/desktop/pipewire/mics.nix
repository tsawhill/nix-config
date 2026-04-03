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
      #   capture side  – auto-connects to the default physical source (node.passive)
      #   playback side – exposed as Audio/Source/Virtual; apps record from here
      extraConfig.pipewire."93-virtual-mic"."context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "Mic Input";
            "capture.props" = {
              "node.name"        = "mic_input_capture";
              "node.description" = "Mic Input Capture";
              "audio.position"   = [ "FL" "FR" ];
              "stream.props"."node.passive" = true;
            };
            "playback.props" = {
              "node.name"        = "mic_input";
              "node.description" = "Mic Input";
              "media.class"      = "Audio/Source/Virtual";
              "audio.position"   = [ "FL" "FR" ];
              # Must exceed the physical USB mic's priority (2109) to be the default source.
              "priority.session" = 2200;
            };
          };
        }
      ];

      # Route all capture apps to the virtual mic input by default.
      # The override rule for mic_input_capture must come last — WirePlumber applies
      # all matching rules in order and later entries win on the same property.
      wireplumber.extraConfig."94-mic-input-routing"."stream.rules" = [
        {
          matches = [ { "media.class" = "Stream/Input/Audio"; } ];
          actions.update-props."node.target" = "mic_input";
        }
        # mic_input_capture is itself a Stream/Input/Audio, so the rule above would
        # route it back to mic_input (a loop). Override it to point at the processed
        # source instead. If presonusmic is disabled, WP falls back to default source.
        {
          matches = [ { "node.name" = "mic_input_capture"; } ];
          actions.update-props."node.target" = "presonus_mic_processed";
        }
      ];
    };
  };
}
