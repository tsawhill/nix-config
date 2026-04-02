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
              "node.description" = "PreSonus → Mic Input";
              "capture.props" = {
                "node.name" = "presonus_to_mic";
                "media.class" = "Audio/Sink";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "presonus_to_mic_out";
              };
            };
          }
        ];
      };
    };

    systemd.user.services.presonus-connect = {
      description = "Connect PreSonus loopback to mic_input sink";
      after = [ "pipewire.service" "wireplumber.service" ];
      bindsTo = [ "pipewire.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "presonus-connect" ''
          for i in {1..10}; do
            ${pkgs.pipewire}/bin/pw-link presonus_to_mic_out:output_FL mic_input:playback_FL 2>/dev/null && \
            ${pkgs.pipewire}/bin/pw-link presonus_to_mic_out:output_FR mic_input:playback_FR 2>/dev/null && exit 0
            sleep 0.5
          done
          exit 1
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
