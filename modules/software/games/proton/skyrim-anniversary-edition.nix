{ lib, ... }:
{
  software.games.entries = {
    skyrimAnniversaryEdition = {
      command = "skyrim";
      desktopName = "The Elder Scrolls V: Skyrim Special Edition";
      category = "The Elder Scrolls";
      basePath = "pc/TES - Skyrim - Anniversary Edition";
      lsfgVk = {
        enable = lib.mkDefault true;
        exe = lib.mkDefault "SkyrimSE.exe";
        multiplier = lib.mkDefault 2;
        flowScale = lib.mkDefault 0.25;
      };
      runner.umu.exe = "skse64_loader.exe";
    };

    skyrimAnniversaryEditionLauncher = {
      command = "skyrim-launcher";
      desktopName = "Skyrim Special Edition Launcher";
      category = "The Elder Scrolls";
      gamescope.resolutions = [ ];
      lsfgVk.enable = false;
      basePath = "pc/TES - Skyrim - Anniversary Edition";
      runner.umu.exe = "SkyrimSELauncher.exe";
    };
  };
}
