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
      # Route PreSonus hardware input → mic_input sink
      wireplumber.extraConfig."95-presonus-routing" = {
        "stream.rules" = [
          {
            matches = [
              { "node.name" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo"; }
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
