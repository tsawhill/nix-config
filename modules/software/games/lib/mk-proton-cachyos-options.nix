{ lib }:

{
  command,
  desktopName,
  exePath ? "/mnt/gameSSD/Games/GH3/GH3.exe",
  prefixPath ? "~/Games/Wine/default",
  protonVersion ? "latest",
  gamescopeArgs ? null,
  env ? [ ],
  lsfgVkEnable ? false,
}:
{
  command = lib.mkOption {
    type = lib.types.str;
    default = command;
    description = "CLI command name for this game launcher.";
  };

  desktopName = lib.mkOption {
    type = lib.types.str;
    default = desktopName;
    description = "Desktop entry display name for this game launcher.";
  };

  exePath = lib.mkOption {
    type = lib.types.str;
    default = exePath;
    description = "Path to the game's executable.";
  };

  prefixPath = lib.mkOption {
    type = lib.types.str;
    default = prefixPath;
    description = "Steam compatibility data path to use for the game's Proton prefix.";
  };

  protonVersion = lib.mkOption {
    type = lib.types.enum [
      "latest"
      "11.0.20260521-3"
    ];
    default = protonVersion;
    description = "proton-cachyos package version for this game launcher.";
  };

  gamescopeArgs = lib.mkOption {
    type = lib.types.nullOr (lib.types.listOf lib.types.str);
    default = gamescopeArgs;
    description = "Optional gamescope arguments. Set to null to launch without gamescope.";
  };

  env = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = env;
    example = [
      "VAR1=aaa"
      "VAR2=bbb"
    ];
    description = "Environment variable assignments to set for this game launcher.";
  };

  lsfgVk.enable = lib.mkEnableOption "lsfg-vk for this game launcher" // {
    default = lsfgVkEnable;
  };
}
