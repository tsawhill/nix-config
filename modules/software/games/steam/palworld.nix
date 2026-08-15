{ lib, ... }:
{
  # Palworld is launched by Steam rather than software.games, so it contributes
  # a config profile without creating a second launcher.
  software.games.lsfgVk.externalProfiles.palworld = {
    enable = lib.mkDefault true;
    exe = lib.mkDefault "Palworld.exe";
    multiplier = lib.mkDefault 2;
    flowScale = lib.mkDefault 0.25;
  };
}
