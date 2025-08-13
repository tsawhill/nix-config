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
          "default.clock.rate" = 44100;
          "default.clock.quantum" = 96;
          "default.clock.min-quantum" = 96;
          "default.clock.max-quantum" = 96;
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
          "pulse.min.req" = "96/44100";
          "pulse.default.req" = "96/44100";
          "pulse.max.req" = "96/44100";
          "pulse.min.quantum" = "96/44100";
          "pulse.max.quantum" = "96/44100";
        };
        "stream.properties" = {
          "node.latency" = "96/44100";
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
