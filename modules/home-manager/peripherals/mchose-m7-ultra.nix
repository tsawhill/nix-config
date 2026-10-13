# My MCHOSE M7 Ultra settings. Hosts override any of them with a plain assignment,
# e.g. my.peripherals.mchose-m7-ultra.pollingRate.wireless = 1000;
{ lib, ... }:
{
  imports = [ ./. ];

  my.peripherals = {
    dryRun = lib.mkDefault false;
    mchose-m7-ultra = {
      enable = true;
    }
    // lib.mapAttrsRecursive (_: lib.mkDefault) {
      dpiStages = [ 1600 ];
      pollingRate = {
        wired = 8000;
        wireless = 8000;
      };
      liftOff = "1mm";
      motionSync = true;
      angleCorrection = -4;
      performanceMode = "gaming";
      sleepMinutes = 10;
      lighting = false;
      buttons.dpi = "disabled";
    };
  };
}
