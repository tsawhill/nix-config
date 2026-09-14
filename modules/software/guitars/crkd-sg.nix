{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    software.apps.gaming.guitarProfiles.crkd-sg = {
      # Decoded from the SDL GUID, not yet confirmed against lsusb. A wrong
      # pair only means the hidraw rule does not match.
      usb = {
        vendor = "3651";
        product = "0010";
      };
      sdl = "0300b280513600000010000005010000,CRKD SG,a:b0,b:b1,y:b3,x:b2,leftshoulder:b4,dpup:h0.1,dpdown:h0.4,back:b6,start:b10,rightx:a3,righty:-a4,dpleft:h0.8,dpright:h0.2,rightshoulder:b5,guide:b8,leftstick:b9,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,platform:Linux,";
      # Not measured yet: re-run guitar-map once the hidraw rule above has been
      # applied and the guitar replugged, then paste its dinput block here.
      dinput = { };
    };
  };
}
