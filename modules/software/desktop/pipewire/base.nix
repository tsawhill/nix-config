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
      default = 128;
      description = "PipeWire default buffer size in samples. Lower = less latency, higher xrun risk.";
    };
    rate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48000;
      description = "PipeWire default sample rate in Hz.";
    };
    maxQuantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 512;
      description = "Largest default PipeWire quantum allowed for the low-latency profile.";
    };
    alsaHeadroom = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Extra ALSA buffering headroom in samples. Defaults to twice the configured quantum.";
    };
    forceStreams = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force every PipeWire and PulseAudio-compatible stream to the configured quantum.";
    };
  };

  config =
    let
      ll = config.my.desktop.audio.lowLatency;
      latency = "${toString ll.quantum}/${toString ll.rate}";
      maxLatency = "${toString ll.maxQuantum}/${toString ll.rate}";
      alsaHeadroom =
        if ll.alsaHeadroom == null then
          ll.quantum * 2
        else
          ll.alsaHeadroom;
      forceQuantumProps = {
        "node.force-quantum" = ll.quantum;
        "node.force-rate" = ll.rate;
      };
      forceQuantumRule = {
        matches = [ { "node.name" = "~.*"; } ];
        actions.update-props = forceQuantumProps;
      };
    in
    {
      security.rtkit.enable = true;

      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        jack.enable = true;
        extraLadspaPackages = with pkgs; [ lsp-plugins rnnoise-plugin ];

        extraConfig.pipewire."92-low-latency" = lib.mkIf ll.enable (
          {
            "context.properties" = {
              "default.clock.rate" = ll.rate;
              "default.clock.quantum" = ll.quantum;
              "default.clock.max-quantum" = ll.maxQuantum;
            };
          }
          // lib.optionalAttrs ll.forceStreams {
            "stream.rules" = [ forceQuantumRule ];
          }
        );

        extraConfig.pipewire-pulse."92-low-latency" = lib.mkIf ll.enable (
          {
            "pulse.properties" = {
              "pulse.min.req" = latency;
              "pulse.default.req" = latency;
              "pulse.default.tlength" = maxLatency;
              "pulse.min.frag" = latency;
              "pulse.default.frag" = latency;
              "pulse.min.quantum" = latency;
            };
          }
          // lib.optionalAttrs ll.forceStreams {
            "pulse.rules" = [
              {
                matches = [ { "node.name" = "~.*"; } ];
                actions.update-props = forceQuantumProps // {
                  "node.latency" = latency;
                };
              }
            ];
          }
        );

        extraConfig.client."92-low-latency" = lib.mkIf (ll.enable && ll.forceStreams) {
          "stream.rules" = [ forceQuantumRule ];
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
                "api.alsa.headroom" = alsaHeadroom;
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
