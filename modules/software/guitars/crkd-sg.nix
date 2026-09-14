{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    software.apps.gaming.guitarProfiles.crkd-sg = {
      # PC mode: xpad claims this device, so it has no hidraw node and the rule
      # generated here is inert. The IDs still match the guitar for the Steam
      # exclusion and for the shim, which is what has to find it.
      usb = {
        vendor = "3651";
        product = "1000";
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
