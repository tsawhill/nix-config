{ lib }:

{
  command,
  desktopName,
  exePath ? "/mnt/gameSSD/Games/GH3/GH3.exe",
  prefixPath ? "$HOME/Games/saves/wine/default",
  protonVersion ? "latest",
  proton ? "cachyos",
  gamescopeArgs ? null,
  gamescopeResolutions ? null,
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

  proton = lib.mkOption {
    type = lib.types.enum [
      "cachyos"
      "ge-proton"
    ];
    default = proton;
    description = ''
      Which Proton build umu runs for this game.
      "cachyos" uses the packaged proton-cachyos, which runs host-native (good for
      64-bit titles). "ge-proton" uses GE-Proton, which runs inside the Steam Runtime
      sniper container -- required for 32-bit titles, whose GPU drivers and fonts only
      resolve inside that container.
    '';
  };

  protonVersion = lib.mkOption {
    type = lib.types.str;
    default = protonVersion;
    description = ''
      Version of the selected Proton, fetched into the nix store at build time.
      For proton = "cachyos": "latest" or e.g. "11.0.20260521-3".
      For proton = "ge-proton": "8-32" / "9-25" / "10-34", or "latest" to let umu
      download and auto-update GE-Proton at runtime instead of pinning.
    '';
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
      software.games.gamescope.resolutions. When multiple resolutions are used,
      launcher commands and desktop entry names include the resolution.
    '';
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
