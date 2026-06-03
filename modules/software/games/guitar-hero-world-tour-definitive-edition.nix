{
  software.games.entries = {
    guitarHeroWorldTourDefinitiveEdition = {
      command = "ghwtde";
      desktopName = "Guitar Hero World Tour: Definitive Edition";
      category = "Guitar Hero";
      # GHWTDE manages its own window; gamescope just leaves it stuck, so run it raw.
      gamescope.resolutions = [ ];
      env = [
        "WINEDLLOVERRIDES=xinput1_3=n,b"
        "vblank_mode=0"
        "PULSE_LATENCY_MSEC=60"
      ];
      runner.umu = {
        exePath = "/mnt/gameSSD/Games/GHWTDE/GHWT_Definitive.exe";
        proton = "ge-proton";
        protonVersion = "9-25";
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
      runner.umu = {
        exePath = "/mnt/gameSSD/Games/GHWTDE/Updater.exe";
        proton = "ge-proton";
        protonVersion = "9-25";
      };
    };
  };
}
