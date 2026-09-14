{
  software.games.entries = {
    guitarHeroWorldTourDefinitiveEdition = {
      command = "ghwtde";
      desktopName = "Guitar Hero World Tour: Definitive Edition";
      category = "Guitar Hero";
      guitarShim.enable = true;
      env = [
        "vblank_mode=0"
      ];
      basePath = "pc/GHWTDE";
      runner.umu = {
        exe = "GHWT_Definitive.exe";
      };
    };

    guitarHeroWorldTourDefinitiveEditionUpdater = {
      command = "ghwtde-updater";
      desktopName = "Guitar Hero World Tour: Definitive Edition Updater";
      category = "Guitar Hero";
      env = [
        "vblank_mode=0"
      ];
      basePath = "pc/GHWTDE";
      network.enable = true;
      runner.umu = {
        exe = "Updater.exe";
      };
    };
  };
}
