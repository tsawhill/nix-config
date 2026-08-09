{
  pkgs,
  ...
}:
{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;

    wireplumber.extraConfig = {
      "10-bluez"."monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = false;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "a2dp_sink" ];
      };
      "11-bluetooth-policy"."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;

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
}
