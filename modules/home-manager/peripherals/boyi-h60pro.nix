# My BOYI H60Pro settings. Hosts override any of them with a plain assignment,
# e.g. my.peripherals.boyi-h60pro.keys.W.actuation = 0.3;
{ lib, ... }:
{
  imports = [ ./. ];

  my.peripherals = {
    dryRun = lib.mkDefault false;
    boyi-h60pro = {
      enable = true;
    }
    // lib.mapAttrsRecursive (_: lib.mkDefault) {
      pollingRate = 8000;
      debounceMs = 0;
      lighting = {
        effect = "circle-wave";
        color = "#802828";
        brightness = 4;
        speed = 1;
      };
      actuation = 1.0;
      keys = {
        W.actuation = 0.5;
        A.actuation = 0.5;
        S.actuation = 0.5;
        D.actuation = 0.5;
      };
      rapidTrigger = {
        enable = true;
        press = 0.2;
        release = 0.2;
      };
    };
  };
}
