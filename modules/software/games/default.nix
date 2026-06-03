{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.software.games;
  directoryContents = builtins.readDir ./.;

  gameModules = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) directoryContents;

  importPaths = map (name: ./. + "/${name}") (builtins.attrNames gameModules);

  resolutionType = lib.types.submodule {
    options = {
      width = lib.mkOption {
        type = lib.types.int;
        description = "Gamescope output and game width.";
      };

      height = lib.mkOption {
        type = lib.types.int;
        description = "Gamescope output and game height.";
      };
    };
  };

  mkGameLauncher = pkgs.callPackage ../../../pkgs/games/mk-game-launcher.nix { };

  mkUmuRunner =
    runnerCfg:
    let
      protonCachyos = pkgs.callPackage ../../../pkgs/games/proton-cachyos.nix {
        version = runnerCfg.protonVersion;
      };

      useGeProton = runnerCfg.proton == "ge-proton";

      geProton = pkgs.callPackage ../../../pkgs/games/proton-ge.nix {
        version = runnerCfg.protonVersion;
      };

      protonPath =
        if useGeProton then
          (if runnerCfg.protonVersion == "latest" then "GE-Proton" else "${geProton}")
        else
          "${protonCachyos}/share/steam/compatibilitytools.d/proton-cachyos";

      runner = pkgs.callPackage ../../../pkgs/games/runners/umu.nix { } {
        inherit (runnerCfg) exePath prefixPath;
        inherit protonPath;
      };
    in
    runner
    // {
      extraPackages = lib.optionals (runnerCfg.proton == "cachyos") [ protonCachyos ];
    };

  mkEmulatorRunner =
    runnerCfg:
    pkgs.callPackage ../../../pkgs/games/runners/emulators/${runnerCfg.type}.nix { } (
      {
        inherit (runnerCfg) gamePath args;
      }
      // lib.optionalAttrs (runnerCfg.type == "retroarch") {
        inherit (runnerCfg) core;
      }
    );

  mkRunner =
    entryCfg:
    if entryCfg.runner.umu != null then
      mkUmuRunner entryCfg.runner.umu
    else if entryCfg.runner.native != null then
      pkgs.callPackage ../../../pkgs/games/runners/native.nix { } entryCfg.runner.native
    else
      mkEmulatorRunner entryCfg.runner.emulator;

  mkEntryPackage =
    entryCfg:
    let
      runner = mkRunner entryCfg;
      gamescopeResolutions =
        if entryCfg.gamescope.resolutions == null then
          cfg.gamescope.resolutions
        else
          entryCfg.gamescope.resolutions;
      gamescopeMode =
        if entryCfg.gamescope.mode == null then
          cfg.gamescope.mode
        else
          entryCfg.gamescope.mode;
      lsfgVkEnable =
        if entryCfg.lsfgVk.enable == null then
          cfg.lsfgVk.enable
        else
          entryCfg.lsfgVk.enable;
    in
    {
      package = mkGameLauncher {
        inherit (entryCfg)
          desktopName
          gamescopeArgs
          env
          ;
        inherit (runner) runnerCommand;
        setupScript = runner.setupScript or "";
        name = entryCfg.command;
        inherit gamescopeMode gamescopeResolutions lsfgVkEnable;
      };
      extraPackages = runner.extraPackages or [ ];
    };

  entryPackages = map mkEntryPackage (lib.attrValues cfg.entries);
in
{
  imports = importPaths;

  options.software.games.exclude = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "guitarHero3" ];
    description = "Game launcher module ids to exclude from the default game library.";
  };

  options.software.games.gamescope.resolutions = lib.mkOption {
    type = lib.types.listOf resolutionType;
    default = [ ];
    description = "Default gamescope resolutions to generate launchers for.";
  };

  options.software.games.gamescope.mode = lib.mkOption {
    type = lib.types.enum [
      "session"
      "direct"
    ];
    default = "session";
    description = ''
      Default gamescope wrapping mode. "session" starts gamescope first and
      launches the game into its nested display. "direct" runs gamescope directly
      around the game command.
    '';
  };

  options.software.games.lsfgVk.enable = lib.mkEnableOption "lsfg-vk for game launchers";

  options.software.games.entries = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          command = lib.mkOption {
            type = lib.types.str;
            description = "CLI command name for this game launcher.";
          };

          desktopName = lib.mkOption {
            type = lib.types.str;
            description = "Desktop entry display name for this game launcher.";
          };

          env = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Environment variable assignments to set for this game launcher.";
          };

          gamescopeArgs = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Extra gamescope arguments appended to generated resolution arguments.";
          };

          gamescope.resolutions = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf resolutionType);
            default = null;
            description = "Gamescope resolutions for this game. Null inherits the global default; an empty list disables gamescope.";
          };

          gamescope.mode = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.enum [
                "session"
                "direct"
              ]
            );
            default = null;
            description = "Gamescope wrapping mode for this game. Null inherits the global default.";
          };

          lsfgVk.enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Whether to enable lsfg-vk for this game. Null inherits the global default.";
          };

          runner.umu = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  exePath = lib.mkOption {
                    type = lib.types.str;
                    description = "Path to the Windows executable.";
                  };

                  prefixPath = lib.mkOption {
                    type = lib.types.str;
                    default = "$HOME/Games/saves/wine/default";
                    description = "Steam compatibility data path to use for the game's Proton prefix.";
                  };

                  proton = lib.mkOption {
                    type = lib.types.enum [
                      "cachyos"
                      "ge-proton"
                    ];
                    default = "cachyos";
                    description = "Which Proton build umu runs for this game.";
                  };

                  protonVersion = lib.mkOption {
                    type = lib.types.str;
                    default = "latest";
                    description = "Version of the selected Proton.";
                  };
                };
              }
            );
            default = null;
            description = "Run this game through umu/Proton.";
          };

          runner.native = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  command = lib.mkOption {
                    type = lib.types.str;
                    description = "Native command or executable path.";
                  };

                  args = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Arguments passed to the native command.";
                  };

                  workingDirectory = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Optional working directory for the native command.";
                  };
                };
              }
            );
            default = null;
            description = "Run this game as a native Linux command.";
          };

          runner.emulator = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  type = lib.mkOption {
                    type = lib.types.enum [
                      "dolphin"
                      "pcsx2"
                      "rpcs3"
                      "retroarch"
                    ];
                    description = "Emulator backend to use.";
                  };

                  gamePath = lib.mkOption {
                    type = lib.types.str;
                    description = "Path to the game, ROM, ISO, or emulator game directory.";
                  };

                  core = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "RetroArch core path. Required when type is retroarch.";
                  };

                  args = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Extra arguments passed to the emulator.";
                  };
                };
              }
            );
            default = null;
            description = "Run this game through an emulator backend.";
          };
        };
      }
    );
    default = { };
    description = "Data-driven game launcher entries.";
  };

  config = {
    assertions = lib.flatten (
      lib.mapAttrsToList (
        entryName: entryCfg:
        let
          enabledRunners = lib.length (
            lib.filter (runnerCfg: runnerCfg != null) [
              entryCfg.runner.umu
              entryCfg.runner.native
              entryCfg.runner.emulator
            ]
          );
        in
        [
          {
            assertion = enabledRunners == 1;
            message = "software.games.entries.${entryName} must configure exactly one runner.";
          }
          {
            assertion =
              entryCfg.runner.emulator == null
              || entryCfg.runner.emulator.type != "retroarch"
              || entryCfg.runner.emulator.core != null;
            message = "software.games.entries.${entryName}.runner.emulator.core is required for retroarch entries.";
          }
        ]
      ) cfg.entries
    );

    environment.systemPackages =
      (map (entryPackage: entryPackage.package) entryPackages)
      ++ lib.flatten (map (entryPackage: entryPackage.extraPackages) entryPackages);
  };
}
