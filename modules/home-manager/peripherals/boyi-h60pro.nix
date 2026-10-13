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
        # Effects, as qmk.top names them: off, always-on, dynamic-breathing, spectrum-cycle,
        #   wave, ripple, starlight, stream, shadow, mountain-wave, sine-wave, color-spring,
        #   flower-wave, kill-two-birds, circle-wave, colorful-cross, snow-fall, meteor, snow-trace.
        # color is any "#rrggbb"; rainbow = true is qmk.top's "Dazzling" (multicolour).
        effect = "mountain-wave";
        rainbow = true;
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
