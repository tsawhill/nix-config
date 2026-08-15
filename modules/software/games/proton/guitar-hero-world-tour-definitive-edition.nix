{ lib, ... }:
{
  software.games.entries = {
    guitarHeroWorldTourDefinitiveEdition = {
      command = "ghwtde";
      desktopName = "Guitar Hero World Tour: Definitive Edition";
      category = "Guitar Hero";
      # GHWTDE manages its own window; gamescope just leaves it stuck, so run it raw.
      gamescope.resolutions = [ ];
      lsfgVk = {
        enable = lib.mkDefault true;
        exe = lib.mkDefault "GHWT_Definitive.exe";
        multiplier = lib.mkDefault 2;
        performanceMode = lib.mkDefault false;
        flowScale = lib.mkDefault 1.0;
        hdrMode = lib.mkDefault false;
        experimentalPresentMode = lib.mkDefault "fifo";
      };
      env = [
        "WINEDLLOVERRIDES=xinput1_3=n,b"
        "vblank_mode=0"
        "PULSE_LATENCY_MSEC=60"
      ];
      basePath = "pc/GHWTDE";
      runner.umu = {
        exe = "GHWT_Definitive.exe";
        proton = "ge-proton";
      };
    };

    guitarHeroWorldTourDefinitiveEditionUpdater = {
      command = "ghwtde-updater";
      desktopName = "Guitar Hero World Tour: Definitive Edition Updater";
      category = "Guitar Hero";
      gamescope.resolutions = [ ];
      env = [
        "vblank_mode=0"
        "PULSE_LATENCY_MSEC=60"
      ];
      basePath = "pc/GHWTDE";
      network.enable = true;
      runner.umu = {
        exe = "Updater.exe";
        proton = "ge-proton";
      };
    };
  };
}
