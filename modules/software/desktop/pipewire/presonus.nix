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
    environment.systemPackages = with pkgs; [
      calf
      zam-plugins
    ];

    services.pipewire = {
      extraConfig.pipewire."94-presonus-loopback" = {
        "context.modules" = [
          {
            name = "libpipewire-module-loopback";
            args = {
              "node.description" = "PreSonus Input";
              "capture.props" = {
                "node.name" = "presonus_input";
                "media.class" = "Audio/Source";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "presonus_playback";
                "media.class" = "Audio/Sink";
              };
            };
          }
        ];
      };

      wireplumber.extraConfig."95-presonus-routing"."stream.rules" = [
        {
          matches = [{ "node.name" = "presonus_playback"; }];
          actions.update-props."node.target" = "mic_input";
        }
      ];
    };
  };
}
