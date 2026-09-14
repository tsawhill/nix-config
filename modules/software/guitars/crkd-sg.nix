{ config, lib, ... }:
{
  config = lib.mkIf config.software.apps.gaming.enable {
    software.apps.gaming.sdlGameControllerMappings = lib.mkAfter [
      "0300b280513600000010000005010000,CRKD SG,a:b0,b:b1,y:b3,x:b2,leftshoulder:b4,dpup:h0.1,dpdown:h0.4,back:b6,start:b10,rightx:a3,righty:-a4,dpleft:h0.8,dpright:h0.2,rightshoulder:b5,guide:b8,leftstick:b9,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,platform:Linux,"
    ];
  };
}
