{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    software.apps.gaming.guitarProfiles.crkd-sg = {
      # Decoded from the SDL GUID, not yet confirmed against lsusb. In PC mode
      # this guitar binds to xpad and exposes no hidraw node, so the rule the
      # usb block generates is inert here -- it still earns the Steam exclusion,
      # and applies if a HID-based mode is ever profiled instead.
      usb = {
        vendor = "3651";
        product = "0010";
      };
      sdl = "0300b280513600000010000005010000,CRKD SG,a:b0,b:b1,y:b3,x:b2,leftshoulder:b4,dpup:h0.1,dpdown:h0.4,back:b6,start:b10,rightx:a3,righty:-a4,dpleft:h0.8,dpright:h0.2,rightshoulder:b5,guide:b8,leftstick:b9,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,platform:Linux,";
      # UNCONFIRMED. guitar-map cannot measure this guitar: with no hidraw node
      # Wine synthesises an Xbox-style descriptor rather than passing the
      # device's own through. This is that synthesised layout's standard order,
      # written so the shim binds the device at all -- it has to match a profile
      # before GUITAR_SHIM_TRACE=1 will log anything. Correct it from the trace.
      dinput = {
        buttons = {
          a = 0;
          b = 1;
          x = 2;
          y = 3;
          leftshoulder = 4;
          back = 6;
          start = 7;
        };
        povs = {
          dpup = 0;
          dpdown = 0;
        };
        axes = {
          rightx = {
            member = "lRx";
            min = 0;
            max = 65535;
          };
        };
      };
    };
  };
}
