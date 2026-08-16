{ lib, ... }:
{
  software.games.entries.ps3RockBand2 = {
    command = "rock-band-2-ps3";
    desktopName = "Rock Band 2 (PS3)";
    category = "Rock Band";
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
    basePath = "ps3/Rock Band 2 (USA).iso";
    runner.emulator.type = "rpcs3";
  };
}
