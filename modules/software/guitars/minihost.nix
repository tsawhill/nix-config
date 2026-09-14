{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    # Adapter profile: other guitars plugged into this adapter can share its
    # GUID. Record a replacement when their exposed inputs differ.
    software.apps.gaming.guitarProfiles.minihost = {
      usb = {
        vendor = "1209";
        product = "2882";
      };
      sdl = "03000000091200008228000001010000,MiniHost GH Guitar,platform:Linux,a:b0,b:b1,x:b3,y:b4,leftshoulder:b6,back:b10,start:b11,dpup:h0.1,dpdown:h0.4,leftx:a0,righty:a2";
      # Transcribed from the table xinput-guitar-dll.c hardcodes today, not
      # measured with guitar-map. Re-record it to confirm.
      dinput = {
        buttons = {
          a = 0;
          b = 1;
          x = 2;
          y = 3;
          leftshoulder = 4;
          back = 6;
          start = [
            7
            11
          ];
        };
        povs = {
          dpup = 0;
          dpdown = 0;
        };
        axes = {
          # Keyed by where the shim sends it, not by the SDL line above: this
          # adapter's whammy is `leftx:a0` for SDL but has always reached games
          # as the right stick X that guitar modes read.
          rightx = {
            member = "lX";
            min = 0;
            max = 65535;
          };
        };
      };
    };
  };
}
