{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.my.desktop.audio.lowLatency = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable low-latency PipeWire tuning (128 quantum @ 48kHz). Disable on devices where this causes audio issues.";
  };

  config = {
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
      extraConfig.pipewire = lib.mkIf config.my.desktop.audio.lowLatency {
        "92-low-latency"."context.properties" = {
          "default.clock.allowed-rates" = [ 44100 48000 88200 96000 ];
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 128;
          "default.clock.quantum-limit" = 128;
          "default.clock.min-quantum" = 128;
          "default.clock.max-quantum" = 128;
        };
      };

      extraConfig.pipewire-pulse = lib.mkIf config.my.desktop.audio.lowLatency {
        "92-low-latency" = {
          "context.properties" = [
            {
              name = "libpipewire-module-protocol-pulse";
              args = { };
            }
          ];
          "pulse.properties" = {
            "pulse.min.req" = "128/48000";
            "pulse.default.req" = "128/48000";
            "pulse.max.req" = "128/48000";
            "pulse.min.quantum" = "128/48000";
            "pulse.max.quantum" = "128/48000";
          };
          "stream.properties" = {
            "node.latency" = "128/48000";
            "resample.quality" = 1;
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
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "hfp_ag" "hsp_ag" ];
        };

        # Don't auto-switch to headset (hands-free) profile on call
        "11-bluetooth-policy"."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;

        # Prevent devices from being suspended when idle
        "12-no-timeout"."wireplumber.settings"."session.suspend-timeout-seconds" = 0;

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
