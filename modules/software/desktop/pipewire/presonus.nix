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

    systemd.user.services.presonus-connect = {
      description = "Connect PreSonus hardware input to mic_input sink";
      after = [ "pipewire.service" "wireplumber.service" ];
      bindsTo = [ "pipewire.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 30;
        ExecStart = pkgs.writeShellScript "presonus-connect" ''
          for i in {1..15}; do
            if ${pkgs.pipewire}/bin/pw-link alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo:capture_FL mic_input:playback_FL 2>/dev/null; then
              ${pkgs.pipewire}/bin/pw-link alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo:capture_FR mic_input:playback_FR 2>/dev/null
              exit 0
            fi
            sleep 0.3
          done
          exit 0
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
