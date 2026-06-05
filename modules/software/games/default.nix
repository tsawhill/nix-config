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

      scale = lib.mkOption {
        type = lib.types.number;
        default = 1.0;
        description = "Scale applied to the in-game gamescope width and height.";
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

  # PS3 titles need rpcs3 built with static libs, matching the emulators bundle
  # (modules/software/bundles/gui-apps/emulators.nix). Without this the entries
  # rpcs3 runner would silently use the stock dynamic build.
  rpcs3Static = pkgs.rpcs3.overrideAttrs (prev: {
    cmakeFlags = prev.cmakeFlags ++ [ (lib.cmakeBool "BUILD_SHARED_LIBS" false) ];
  });

  mkEmulatorRunner =
    runnerCfg:
    pkgs.callPackage ../../../pkgs/games/runners/emulators/${runnerCfg.type}.nix (
      lib.optionalAttrs (runnerCfg.type == "rpcs3") { rpcs3 = rpcs3Static; }
    ) (
      {
        inherit (runnerCfg) gamePath args;
      }
      // lib.optionalAttrs (runnerCfg.type == "retroarch") {
        inherit (runnerCfg) core;
      }
    );

  # When a host opts a game into local mode (software.games.localGames), the
  # runner's game path is relocated under localPath, keeping the original
  # filename. localPath is the *folder* holding the file, so the basename of the
  # default (network-share) path is appended. Only umu and emulator runners
  # reference on-disk game files; native commands are left untouched.
  mkRunner =
    useLocal: localPath: entryCfg:
    if entryCfg.runner.umu != null then
      mkUmuRunner (
        entryCfg.runner.umu
        // lib.optionalAttrs useLocal {
          exePath = "${localPath}/${baseNameOf entryCfg.runner.umu.exePath}";
        }
      )
    else if entryCfg.runner.native != null then
      pkgs.callPackage ../../../pkgs/games/runners/native.nix { } entryCfg.runner.native
    else
      mkEmulatorRunner (
        entryCfg.runner.emulator
        // lib.optionalAttrs useLocal {
          gamePath = "${localPath}/${baseNameOf entryCfg.runner.emulator.gamePath}";
        }
      );

  mkEntryPackage =
    id: entryCfg:
    let
      useLocal = lib.elem id cfg.localGames && entryCfg.localPath != null;
      runner = mkRunner useLocal entryCfg.localPath entryCfg;
      gamescopeResolutions =
        if entryCfg.gamescope.resolutions == null then
          cfg.gamescope.resolutions
        else
          entryCfg.gamescope.resolutions;
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
        inherit gamescopeResolutions lsfgVkEnable;
      };
      extraPackages = runner.extraPackages or [ ];
    };

  includedEntries = lib.filterAttrs (name: _: !(lib.elem name cfg.exclude)) cfg.entries;
  entryPackages = lib.mapAttrsToList mkEntryPackage includedEntries;

  # Human-facing platform category per game, derived from its runner. Used to
  # group games into collections in frontends (Pegasus, Steam shortcuts).
  emulatorCategories = {
    rpcs3 = "PS3";
    dolphin = "GameCube/Wii";
    pcsx2 = "PS2";
    retroarch = "RetroArch";
  };
  entryCategory =
    entryCfg:
    if entryCfg.category != null then
      entryCfg.category
    else if entryCfg.runner.umu != null then
      "Proton"
    else if entryCfg.runner.native != null then
      "Native"
    else
      emulatorCategories.${entryCfg.runner.emulator.type};

  # Read-only manifest of enabled games for frontends. One attrset per game.
  gamesManifest = lib.mapAttrsToList (id: entryCfg: {
    inherit id;
    name = entryCfg.desktopName;
    command = entryCfg.command;
    category = entryCategory entryCfg;
  }) includedEntries;
in
{
  imports = importPaths;

  options.software.games.exclude = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "guitarHero3" ];
    description = "Game launcher module ids to exclude from the default game library.";
  };

  options.software.games.localGames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "guitarHero3"
      "ps3GuitarHero3"
    ];
    description = ''
      Game entry ids to launch from their localPath instead of the default
      (network share) path on this host. Each listed entry must define localPath
      and use a umu or emulator runner. Useful for hosts (e.g. a Steam Deck) that
      keep certain games on local disk and aren't always on the LAN.
    '';
  };

  # Internal: consumed by frontend home-manager modules via osConfig.
  options.software.games.manifest = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.str);
    internal = true;
    default = [ ];
    description = "Enabled game launchers as {id,name,command,category} for frontends (Pegasus, Steam).";
  };

  options.software.games.gamescope.resolutions = lib.mkOption {
    type = lib.types.listOf resolutionType;
    default = [ ];
    description = "Default gamescope resolutions to generate launchers for.";
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

          category = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Guitar Hero";
            description = ''
              Custom frontend category for this game (groups it in Pegasus
              collections and Steam categories). When null, the runner type is
              used: Proton, PS3, GameCube/Wii, PS2, RetroArch, or Native.
            '';
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

          localPath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/home/taylor/Games/local/GH3";
            description = ''
              Local directory holding this game's files: the folder containing the
              ROM/ISO for emulator runners, or the folder containing the .exe for
              umu/Proton runners. On hosts that list this entry id in
              software.games.localGames, the launcher loads the game from
              "<localPath>/<basename of the default path>" instead of the default
              (network share) path. Use an absolute path (dolphin/pcsx2/retroarch
              do not expand $HOME).
            '';
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
    )
    ++ map (
      id:
      let
        entry = cfg.entries.${id} or null;
      in
      {
        assertion =
          entry != null
          && entry.localPath != null
          && (entry.runner.umu != null || entry.runner.emulator != null);
        message = "software.games.localGames entry \"${id}\" must exist in software.games.entries, define localPath, and use a umu or emulator runner.";
      }
    ) cfg.localGames;

    software.games.manifest = gamesManifest;

    environment.systemPackages =
      (map (entryPackage: entryPackage.package) entryPackages)
      ++ lib.flatten (map (entryPackage: entryPackage.extraPackages) entryPackages);
  };
}
