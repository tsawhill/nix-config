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
              "media.class" = "Audio/Source";
              "node.class" = "Stream";
              "filter.graph" = {
                nodes = [
                  {
                    type = "builtin";
                    name = "passthrough";
                  }
                ];
                links = [];
              };
            };
          }
        ];
      };

      # Route: PreSonus hardware input → filter-chain effects → mic_input sink
      wireplumber.extraConfig."95-presonus-routing" = {
        "stream.rules" = [
          # Route PreSonus hardware to the effects filter
          {
            matches = [
              { "node.name" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo"; }
            ];
            actions.update-props = {
              "node.target.object" = "presonus_mic_effects";
            };
          }
          # Route the effects output to the mic_input sink (for apps to record from)
          {
            matches = [
              { "node.name" = "presonus_mic_effects"; }
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
