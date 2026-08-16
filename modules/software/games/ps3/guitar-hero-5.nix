{ lib, ... }:
{
  software.games.entries.ps3GuitarHero5 = {
    command = "gh5-ps3";
    desktopName = "Guitar Hero 5 (PS3)";
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
    basePath = "ps3/Guitar Hero 5 (USA) (En,Fr).iso";
    runner.emulator.type = "rpcs3";
  };
}
