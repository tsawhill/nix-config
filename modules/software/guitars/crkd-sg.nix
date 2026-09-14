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
      # Derived from the sdl line above, not measured: with no hidraw node Wine
      # synthesises the descriptor from what SDL reports, passing joystick
      # indices through in order, so DirectInput index N is SDL index N. Axes
      # follow the same order into X/Y/Z/Rx/Ry/Rz, and dinput reports its
      # default 0..65535 range rather than SDL's signed one.
      dinput = {
        buttons = {
          a = 0; # b0, green
          b = 1; # b1, red
          x = 2; # b2, blue
          y = 3; # b3, yellow
          leftshoulder = 4; # b4, orange
          back = 6; # b6
          start = 10; # b10, where this guitar reports it
        };
        povs = {
          dpup = 0; # h0, strum up
          dpdown = 0; # h0, strum down
        };
        axes = {
          rightx = {
            member = "lRx"; # a3, whammy
            min = 0;
            max = 65535;
          };
          righty = {
            member = "lRy"; # a4, tilt
            min = 0;
            max = 65535;
          };
        };
      };
    };
  };
}
