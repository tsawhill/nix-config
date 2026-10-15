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
      lighting.effect = "snow-trace";
      lighting.brightness = 4;
      lighting.speed = 1;
      lighting.color = "#802828";
      lighting.rainbow = true;
      fnLayer = 0;
      antiMistouch = false;
      rtStabilityMs = 0;
      wasdSwap = false;
      actuation = 2.100;
      rapidTrigger.enable = true;
      rapidTrigger.press = 0.200;
      rapidTrigger.release = 0.200;
      bottomDeadzone = 0.300;
      keys."A".actuation = 0.100;
      keys."D".actuation = 0.100;
      keys."S".actuation = 0.100;
      keys."W".actuation = 0.100;
    };
  };
}
