{ lib }:

{
  command,
  desktopName,
  gamePath,
  gamescopeResolutions ? [
    {
      width = 2560;
      height = 1440;
    }
  ],
  args ? [ ],
  gamescopeArgs ? null,
  env ? [ ],
  lsfgVkEnable ? false,
}:
{
  command = lib.mkOption {
    type = lib.types.str;
    default = command;
    description = "CLI command name for this RPCS3 game launcher.";
  };

  desktopName = lib.mkOption {
    type = lib.types.str;
    default = desktopName;
    description = "Desktop entry display name for this RPCS3 game launcher.";
  };

  gamePath = lib.mkOption {
    type = lib.types.str;
    default = gamePath;
    description = "Path to the game ISO, or a filename relative to the RPCS3 default game directory.";
  };

  args = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = args;
    description = "Extra arguments passed to RPCS3.";
  };

  gamescopeArgs = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = gamescopeArgs;
    description = "Extra gamescope arguments appended to generated resolution launchers.";
  };

  gamescope.resolutions = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.listOf (
        lib.types.submodule {
          options = {
            width = lib.mkOption {
              type = lib.types.int;
              description = "Gamescope output and game width.";
            };

            height = lib.mkOption {
              type = lib.types.int;
              description = "Gamescope output and game height.";
            };

            scale = lib.mkOption {
              type = lib.types.number;
              default = 1.0;
              description = "Scale applied to the in-game gamescope width and height.";
            };
          };
        }
      )
    );
    default = gamescopeResolutions;
    description = ''
      Gamescope resolutions to generate launchers for. When null, uses
      software.games.gamescope.resolutions. When empty, disables gamescope variants.
    '';
  };

  env = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = env;
    description = "Environment variable assignments to set for this RPCS3 game launcher.";
  };

  lsfgVk.enable = lib.mkEnableOption "lsfg-vk for this RPCS3 game launcher" // {
    default = lsfgVkEnable;
  };
}
