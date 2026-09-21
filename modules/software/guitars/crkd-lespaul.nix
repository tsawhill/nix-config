
{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    software.apps.gaming.guitarProfiles."crkd-lespaul" = {
      usb = {
        vendor = "1430";
        product = "4748";
      };
      sdl = "0300dd69301400004847000022310000,RedOctane Guitar Hero X-plorer,a:b0,b:b1,y:b3,x:b2,leftshoulder:b4,dpup:h0.1,dpdown:h0.4,back:b6,rightx:a3,righty:-a4,dpleft:h0.8,dpright:h0.2,rightshoulder:b5,guide:b8,leftstick:b9,rightstick:b7,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,misc1:b6,start:b10,platform:Linux,";
      # Derived from the sdl line above, not measured: this device exposes
      # no hidraw node, so Wine synthesises its descriptor from what SDL
      # reports and joystick indices pass through in order. Confirm with a
      # traced launch (GUITAR_SHIM_TRACE=1) if a control misbehaves.
      dinput = {
        buttons = {
          a = 0;
          b = 1;
          y = 3;
          x = 2;
          leftshoulder = 4;
          back = 6;
          start = 10;
          rightshoulder = 5;
          guide = 8;
          leftstick = 9;
          rightstick = 7;
          misc1 = 6;
        };
        povs = {
          dpup = 0;
          dpdown = 0;
          dpleft = 0;
          dpright = 0;
        };
        axes = {
          rightx = {
            member = "lRx";
            min = 0;
            max = 65535;
          };
          righty = {
            member = "lRy";
            min = 0;
            max = 65535;
          };
          lefttrigger = {
            member = "lZ";
            min = 0;
            max = 65535;
          };
          righttrigger = {
            member = "lRz";
            min = 0;
            max = 65535;
          };
          leftx = {
            member = "lX";
            min = 0;
            max = 65535;
          };
          lefty = {
            member = "lY";
            min = 0;
            max = 65535;
          };
        };
      };
    };
  };
}