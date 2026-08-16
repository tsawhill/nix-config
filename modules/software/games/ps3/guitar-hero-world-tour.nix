{ lib, ... }:
{
  software.games.entries.ps3GuitarHeroWorldTour = {
    command = "gh-world-tour-ps3";
    desktopName = "Guitar Hero World Tour (PS3)";
    category = "Guitar Hero";
    gamescope.resolutions = [
      {
        width = 2560;
        height = 1440;
      }
    ];
    lsfgVk = {
      enable = lib.mkDefault true;
      multiplier = lib.mkDefault 2;
    };
    basePath = "ps3/Guitar Hero World Tour (USA) (En,Fr).iso";
    runner.emulator.type = "rpcs3";
  };
}
