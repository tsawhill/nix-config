{
  pkgs,
  ...
}:
{
  # rtkit is optional but recommended
  security.rtkit.enable = true;

  # Enable pipewire and pipewire-pulse.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    extraConfig.pipewire = {
      "92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 192;
          "default.clock.min-quantum" = 192;
          "default.clock.max-quantum" = 192;
        };
      };
    };

    extraConfig.pipewire-pulse = {
      "92-low-latency" = {
        "context.properties" = [
          {
            name = "libpipewire-module-protocol-pulse";
            args = { };
          }
        ];
        "pulse.properties" = {
          "pulse.min.req" = "192/48000";
          "pulse.default.req" = "192/48000";
          "pulse.max.req" = "192/48000";
          "pulse.min.quantum" = "192/48000";
          "pulse.max.quantum" = "192/48000";
        };
        "stream.properties" = {
          "node.latency" = "192/48000";
          "resample.quality" = 1;
        };
      };
    };

    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = false;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [
            "a2dp_sink"
          ];
        };
      };
      "11-bluetooth-policy" = {
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
    };

  };

  # Include pulseaudio package for cli audio control
  environment.systemPackages = with pkgs; [
    pulseaudio
  ];
}
