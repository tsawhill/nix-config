{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.my.desktop.audio.lowLatency = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable low-latency PipeWire tuning.";
    };
    quantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "PipeWire default buffer size in samples. Lower = less latency, higher xrun risk.";
    };
    rate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48000;
      description = "PipeWire default sample rate in Hz.";
    };
  };

  config =
    let
      ll = config.my.desktop.audio.lowLatency;
    in
    {
      security.rtkit.enable = true;

      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        jack.enable = true;

        extraConfig.pipewire."92-low-latency"."context.properties" = lib.mkIf ll.enable {
          "default.clock.quantum" = ll.quantum;
          "default.clock.max-quantum" = ll.quantum * 2;
        };

        wireplumber.extraConfig = {
          "10-bluez"."monitor.bluez.properties" = {
            "bluez5.enable-sbc-xq" = true;
            "bluez5.enable-msbc" = false;
            "bluez5.enable-hw-volume" = true;
            "bluez5.roles" = [ "a2dp_sink" ];
          };
          "11-bluetooth-policy"."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
          "12-no-timeout"."wireplumber.settings"."session.suspend-timeout-seconds" = 0;

          # Give ALSA USB driver buffering headroom at low quantum
          "13-alsa-period"."monitor.alsa.rules" = lib.mkIf ll.enable [
            {
              matches = [ { "node.name" = "~alsa_.*"; } ];
              actions.update-props = {
                "api.alsa.period-size" = ll.quantum;
                "api.alsa.headroom" = ll.quantum;
                "api.alsa.period-num" = 4;
                # "api.alsa.disable-batch" = true;
              };
            }
          ];

          # Device priority: bluetooth > USB > PCIe
          "51-device-priority" = {
            "monitor.bluez.rules" = [
              {
                matches = [ { "node.name" = "~bluez_output.*"; } ];
                actions.update-props = {
                  "priority.session" = 1050;
                  "priority.driver" = 1050;
                };
              }
            ];
            "monitor.alsa.rules" = [
              {
                matches = [ { "node.name" = "~alsa_output.*usb.*"; } ];
                actions.update-props = {
                  "priority.session" = 1025;
                  "priority.driver" = 1025;
                };
              }
              {
                matches = [ { "node.name" = "~alsa_output.*pci.*"; } ];
                actions.update-props = {
                  "priority.session" = 1000;
                  "priority.driver" = 1000;
                };
              }
            ];
          };
        };
      };

      environment.systemPackages = [
        pkgs.pulseaudio
        pkgs.pavucontrol
      ];
    };
}
