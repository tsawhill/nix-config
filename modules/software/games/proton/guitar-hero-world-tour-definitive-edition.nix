{ config, lib, ... }:
let
  # Guitar layouts come from modules/software/guitars profiles; without it the
  # DLL falls back to the MiniHost layout it used to hardcode.
  shimConfig = config.software.apps.gaming.guitarShimConfig or "";
in
{
  software.games.entries = {
    guitarHeroWorldTourDefinitiveEdition = {
      command = "ghwtde";
      desktopName = "Guitar Hero World Tour: Definitive Edition";
      category = "Guitar Hero";
      env = [
        "WINEDLLOVERRIDES=xinput1_3=n,b"
        "vblank_mode=0"
      ]
      ++ lib.optional (shimConfig != "") "GUITAR_SHIM_CONFIG=${shimConfig}";
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
