{ lib, config, pkgs, ... }:
let
  cfg = config.my.audio.presonus;
in
{
  options.my.audio.presonus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable PreSonus mic with effects chain (gate, noise removal, deesser, etc.)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install LV2/LADSPA plugins needed for effects
    environment.systemPackages = with pkgs; [
      calf                # Gate, deesser, reverb, loudness, compressor
      zam-plugins         # Additional deesser/gate options
    ];

    services.pipewire = {
      # Add the mic effects filter chain
      extraConfig.pipewire."94-presonus-effects" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "PreSonus Mic Effects";
              "media.name" = "PreSonus Mic Effects";
              "filter.graph" = {
                nodes = [
                  # Gate (threshold -27dB, reduction -40dB, attack 5ms, release 100ms)
                  {
                    factory = "ladspa";
                    plugin = "http://calf.sourceforge.net/plugins/Gate";
                    label = "Gate";
                    control = {
                      "Threshold" = -27.0;
                      "Ratio" = 10.0;
                      "Attack" = 5.0;
                      "Release" = 100.0;
                      "Makeup Gain" = 0.0;
                    };
                  }
                  # Deesser (de-esser for sibilance control)
                  {
                    factory = "ladspa";
                    plugin = "http://calf.sourceforge.net/plugins/Deesser";
                    label = "Deesser";
                  }
                  # Reverb
                  {
                    factory = "ladspa";
                    plugin = "http://calf.sourceforge.net/plugins/Reverb";
                    label = "Reverb";
                  }
                  # Loudness (loudness compensation)
                  {
                    factory = "ladspa";
                    plugin = "http://calf.sourceforge.net/plugins/Loudness";
                    label = "Loudness";
                  }
                  # Compressor (dynamic range compression)
                  {
                    factory = "ladspa";
                    plugin = "http://calf.sourceforge.net/plugins/Compressor";
                    label = "Compressor";
                  }
                ];
                links = [
                  { output = "Gate:Out L"; input = "Deesser:In L"; }
                  { output = "Gate:Out R"; input = "Deesser:In R"; }
                  { output = "Deesser:Out L"; input = "Reverb:In L"; }
                  { output = "Deesser:Out R"; input = "Reverb:In R"; }
                  { output = "Reverb:Out L"; input = "Loudness:In L"; }
                  { output = "Reverb:Out R"; input = "Loudness:In R"; }
                  { output = "Loudness:Out L"; input = "Compressor:In L"; }
                  { output = "Loudness:Out R"; input = "Compressor:In R"; }
                ];
              };
              "capture.props" = {
                "node.name" = "presonus_mic_effects";
                "media.class" = "Audio/Source";
                "audio.position" = [ "FL" "FR" ];
              };
            };
          }
        ];
      };

      # Route PreSonus hardware input → effects filter → mic sink
      wireplumber.extraConfig."95-presonus-routing" = {
        "stream.rules" = [
          {
            matches = [
              { "node.name" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo"; }
            ];
            actions.update-props = {
              "node.target.object" = "presonus_mic_effects";
            };
          }
          {
            matches = [
              { "node.name" = "presonus_mic_input"; }
            ];
            actions.update-props = {
              "node.target.object" = "mic_input";
            };
          }
        ];
      };
    };
  };
}
