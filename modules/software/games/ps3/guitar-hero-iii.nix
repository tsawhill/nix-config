{ lib, ... }:
{
  software.games.entries.ps3GuitarHero3 = {
    command = "gh3-ps3";
    desktopName = "Guitar Hero III: Legends of Rock (PS3)";
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
    basePath = "ps3/Guitar Hero III - Legends of Rock (USA).iso";
    runner.emulator.type = "rpcs3";
  };
}
