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
      extraConfig.pipewire."94-presonus-loopback" = {
        "context.modules" = [
          {
            name = "libpipewire-module-loopback";
            args = {
              "node.description" = "PreSonus → Mic Input";
              "capture.props" = {
                "node.name" = "presonus_to_mic";
                "media.class" = "Audio/Sink";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "presonus_to_mic_out";
                "media.class" = "Audio/Source";
              };
            };
          }
        ];
      };
    };

    # Establish the connection after PipeWire starts
    systemd.user.services.presonus-link = {
      description = "Link PreSonus loopback to mic input";
      after = [ "pipewire.service" ];
      partOf = [ "pipewire.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.pipewire}/bin/pw-link presonus_to_mic_out:output_FL mic_input:playback_FL && ${pkgs.pipewire}/bin/pw-link presonus_to_mic_out:output_FR mic_input:playback_FR";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
