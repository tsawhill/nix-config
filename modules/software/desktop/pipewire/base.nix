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
      description = "Enable low-latency PipeWire tuning. Disable on devices where this causes audio issues.";
    };
    quantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "PipeWire buffer size in samples for output. Lower = less latency, higher xrun risk. Powers of 2 (32, 64, 128).";
    };
    inputQuantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "ALSA period size for input devices. rnnoise requires 480. Must match filter chain node.latency.";
    };
    rate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48000;
      description = "PipeWire default sample rate in Hz.";
    };
};

  config = let
    ll = config.my.desktop.audio.lowLatency;
    q  = toString ll.quantum;
    r  = toString ll.rate;
  in {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      jack.enable = true;

      ##############################
      #       Low-latency tuning   #
      ##############################
      extraConfig.pipewire = lib.mkIf ll.enable {
        "92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = ll.rate;
            "default.clock.quantum" = ll.quantum;
            "default.clock.min-quantum" = ll.quantum;
            "default.clock.max-quantum" = ll.quantum;
            "default.clock.quantum-limit" = ll.quantum;
          };
          "stream.properties" = {
            "node.latency" = "${q}/${r}";
            "resample.quality" = 4;
          };
        };
      };

      extraConfig.pipewire-pulse = lib.mkIf ll.enable {
        "92-low-latency" = {
          "pulse.properties" = {
            "pulse.min.req" = "${q}/${r}";
            "pulse.default.req" = "${q}/${r}";
            "pulse.max.req" = "1024/${r}";
            "pulse.min.quantum" = "${q}/${r}";
            "pulse.max.quantum" = "1024/${r}";
          };
          "stream.properties" = {
            "node.latency" = "${q}/${r}";
            "resample.quality" = 4;
          };
        };
      };

      ##############################
      #       WirePlumber rules    #
      ##############################
      wireplumber.extraConfig = {

        # Bluetooth codec and profile settings
        "10-bluez"."monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = false;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [ "a2dp_sink" ];
        };

        # Don't auto-switch to headset (hands-free) profile on call
        "11-bluetooth-policy"."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;

        # Prevent devices from being suspended when idle
        "12-no-timeout"."wireplumber.settings"."session.suspend-timeout-seconds" = 0;

        # Set ALSA period size on all PreSonus nodes (pro profile splits into
        # separate input/output devices — both need explicit period-size or
        # the USB device garbles at unsupported sizes)
        "13-presonus-period"."monitor.alsa.rules" = lib.mkIf ll.enable [
          {
            matches = [ { "alsa.card_name" = "Studio 24c"; } ];
            actions.update-props."api.alsa.period-size" = ll.inputQuantum;
          }
        ];

        # Prevent input from becoming graph driver on pro profile
        "13-input-priority"."monitor.alsa.rules" = [
          {
            matches = [ { "node.name" = "~alsa_input.*PreSonus*"; } ];
            actions.update-props."priority.driver" = 900;
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

    # pactl+pavucontrol to control audio
    environment.systemPackages = [
      pkgs.pulseaudio
      pkgs.pavucontrol
    ];
  };
}
