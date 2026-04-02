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
      # Route PreSonus hardware input directly to mic_input sink
      extraConfig.pipewire."94-presonus-routing" = {
        "context.modules" = [
          {
            name = "libpipewire-module-loopback";
            args = {
              "node.description" = "PreSonus Input";
              "capture.props" = {
                "node.name" = "presonus_capture";
                "media.class" = "Audio/Source";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "presonus_output";
                "media.class" = "Audio/Sink";
              };
            };
          }
        ];
      };

      wireplumber.extraConfig."95-presonus-routing"."stream.rules" = [
        {
          matches = [{ "node.name" = "presonus_output"; }];
          actions.update-props."target.object" = "mic_input";
        }
      ];
    };
  };
}
