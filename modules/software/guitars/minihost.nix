{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    # Adapter profile: other guitars plugged into this adapter can share its
    # GUID. Record a replacement when their exposed inputs differ.
    software.apps.gaming = {
      sdlGameControllerMappings = lib.mkBefore [
        "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2"
      ];
      steamIgnoredGuitarDevices = [ "0x1209/0x2882" ];
    };

    # Wine's raw HID path needs access to the MiniHost hidraw node.
    services.udev.extraRules = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="2882", GROUP="input", MODE="0660", TAG+="uaccess"
    '';
  };
}
