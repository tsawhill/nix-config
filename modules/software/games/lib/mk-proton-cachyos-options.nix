{ lib }:

{
  command,
  desktopName,
  exePath ? "/mnt/gameSSD/Games/GH3/GH3.exe",
  prefixPath ? "~/Games/Wine/default",
  protonVersion ? "latest",
  proton ? "cachyos",
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
    description = "proton-cachyos package version (only used when proton = \"cachyos\").";
  };

  proton = lib.mkOption {
    type = lib.types.enum [
      "cachyos"
      "ge-proton"
    ];
    default = proton;
    description = ''
      Which Proton build umu runs for this game.
      "cachyos" uses the packaged proton-cachyos, which runs host-native (good for
      64-bit titles). "ge-proton" uses GE-Proton, which umu auto-downloads and runs
      inside the Steam Runtime sniper container -- required for 32-bit titles, whose
      GPU drivers and fonts only resolve inside that container.
    '';
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
