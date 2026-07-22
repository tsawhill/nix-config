{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.software.games;

  # Auto-import every game entry file (recursively, so games can live in
  # per-platform subdirs like proton/ and ps3/). default.nix itself is excluded.
  collectNix =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          collectNix (dir + "/${name}")
        else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  importPaths = collectNix ./.;

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
    umuCfg: exePath:
    let
      protonCachyos = pkgs.callPackage ../../../pkgs/games/proton-cachyos.nix {
        version = umuCfg.protonVersion;
      };

      useGeProton = umuCfg.proton == "ge-proton";

      geProton = pkgs.callPackage ../../../pkgs/games/proton-ge.nix {
        version = umuCfg.protonVersion;
      };

      protonPath =
        if useGeProton then
          (if umuCfg.protonVersion == "latest" then "GE-Proton" else "${geProton}")
        else
          "${protonCachyos}/share/steam/compatibilitytools.d/proton-cachyos";

      runner = pkgs.callPackage ../../../pkgs/games/runners/umu.nix { } {
        inherit exePath protonPath;
        inherit (umuCfg) prefixPath;
      };
    in
    runner
    // {
      extraPackages = lib.optionals (umuCfg.proton == "cachyos") [ protonCachyos ];
    };

  mkEmulatorRunner =
    emuCfg: gamePath:
    pkgs.callPackage ../../../pkgs/games/runners/emulators/${emuCfg.type}.nix { } (
      {
        inherit gamePath;
        inherit (emuCfg) args;
      }
      // lib.optionalAttrs (emuCfg.type == "retroarch") {
        inherit (emuCfg) core;
      }
    );

  # CIFS mount of the full library, mounted at the server's own path on every
  # gaming host so a game's basePath resolves identically everywhere.
  cifsRoot = "/mnt/zpool/roms";

  # A basePath under the roms root is relative; absolute paths (/, ~, $HOME) are
  # one-off launchers that never sync and always launch from where they point.
  isRelative = p: !(lib.hasPrefix "/" p || lib.hasPrefix "~" p || lib.hasPrefix "$HOME" p);

  # Platform = first path segment of a relative basePath (pc, ps3, wii, …).
  platformOf =
    entryCfg:
    if entryCfg.basePath != null && isRelative entryCfg.basePath then
      lib.head (lib.splitString "/" entryCfg.basePath)
    else
      null;

  syncAll = lib.elem "*" cfg.syncPlatforms;

  # Whether this host keeps a local synced copy of the game.
  isSelected =
    id: entryCfg:
    entryCfg.basePath != null
    && isRelative entryCfg.basePath
    && (
      syncAll
      || lib.elem id cfg.syncGames
      || (platformOf entryCfg != null && lib.elem (platformOf entryCfg) cfg.syncPlatforms)
    );

  # Base the launcher reads the game from: the local synced copy when selected,
  # otherwise the CIFS library mount; absolute basePaths are used as-is.
  baseDir =
    id: entryCfg:
    let
      bp = entryCfg.basePath;
    in
    if bp == null then
      null
    else if !(isRelative bp) then
      bp
    else if isSelected id entryCfg then
      "${cfg.syncRoot}/${bp}"
    else
      "${cifsRoot}/${bp}";

  mkRunner =
    id: entryCfg:
    let
      base = baseDir id entryCfg;
    in
    if entryCfg.runner.umu != null then
      mkUmuRunner entryCfg.runner.umu "${base}/${entryCfg.runner.umu.exe}"
    else if entryCfg.runner.native != null then
      pkgs.callPackage ../../../pkgs/games/runners/native.nix { } entryCfg.runner.native
    else
      mkEmulatorRunner entryCfg.runner.emulator base;

  mkEntryPackage =
    id: entryCfg:
    let
      runner = mkRunner id entryCfg;
      gamescopeResolutions =
        if entryCfg.gamescope.resolutions == null then
          cfg.gamescope.resolutions
        else
          entryCfg.gamescope.resolutions;
      lsfgVkEnable =
        if entryCfg.lsfgVk.enable == null then cfg.lsfgVk.enable else entryCfg.lsfgVk.enable;
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

  # --- Selective sync (see ./default.nix header docs / the roms Syncthing share) ---

  # Relative basePaths of the individually-selected syncable games on this host.
  selectedGamePaths = lib.filter (p: p != null) (
    map (
      id:
      let
        e = cfg.entries.${id} or null;
      in
      if e != null && e.basePath != null && isRelative e.basePath then e.basePath else null
    ) cfg.syncGames
  );

  # Whole platforms selected (excluding the "*" sync-all wildcard).
  wholePlatforms = lib.filter (p: p != "*") cfg.syncPlatforms;
  coveredByPlatform = p: lib.elem (lib.head (lib.splitString "/" p)) wholePlatforms;
  specificGamePaths = lib.unique (lib.filter (p: !(coveredByPlatform p)) selectedGamePaths);
  ancestorsOf =
    p:
    let
      parts = lib.splitString "/" p;
    in
    map (k: lib.concatStringsSep "/" (lib.take k parts)) (lib.range 1 (lib.length parts - 1));
  specificAncestors = lib.unique (lib.concatMap ancestorsOf specificGamePaths);
  # Dirs we descend into and must exclude the non-selected children of;
  # a wholesale platform's whole subtree is kept, so it is not excluded.
  excludeDirs = lib.filter (d: !(lib.elem d wholePlatforms)) specificAncestors;

  pathDirectChildOf =
    parent: path:
    let
      parentParts = lib.splitString "/" parent;
      pathParts = lib.splitString "/" path;
      parentDepth = lib.length parentParts;
    in
    if lib.take parentDepth pathParts == parentParts && lib.length pathParts > parentDepth then
      lib.concatStringsSep "/" (lib.take (parentDepth + 1) pathParts)
    else
      null;
  keepChildrenOf =
    parent: lib.unique (lib.filter (p: p != null) (map (pathDirectChildOf parent) specificGamePaths));
  pruneKeepFile =
    parent:
    pkgs.writeText "game-local-keep-${lib.replaceStrings [ "/" " " ] [ "-" "-" ] parent}" (
      lib.concatStringsSep "\n" (keepChildrenOf parent) + "\n"
    );

  # Top-level roots this host manages under syncRoot (for the prune manifest).
  managedPaths = lib.unique (wholePlatforms ++ selectedGamePaths);

  # .stignore lines for the roms share: whitelist the selected platforms/games,
  # exclude everything else. Empty (no restriction, full sync) when "*" is set.
  romsIgnores =
    if syncAll then
      [ ]
    else
      let
        depth = p: lib.length (lib.splitString "/" p);
        byDepthDesc = lib.sort (a: b: depth a > depth b);
        recursiveIncludes = wholePlatforms ++ specificGamePaths;
        selectedIncludes = lib.unique ((map (p: p + "/**") recursiveIncludes) ++ recursiveIncludes);
        ancestorRules = d: [
          ("/" + d + "/*")
          ("!/" + d)
        ];
      in
      # Selected game/platform directories need both the directory itself and its
      # contents included. Ancestors must be included after their sibling excludes,
      # because a directory include also matches its subtree in Syncthing.
      (map (p: "!/" + p) (byDepthDesc selectedIncludes))
      ++ lib.concatMap ancestorRules (byDepthDesc excludeDirs)
      ++ [ "*" ];

  hasSelection = cfg.syncGames != [ ] || cfg.syncPlatforms != [ ];

  # Manifest of currently-managed roots; the prune diffs the previous run against
  # this to delete de-selected local copies.
  managedFile = pkgs.writeText "game-local-managed" (lib.concatStringsSep "\n" managedPaths + "\n");
in
{
  imports = importPaths;

  options.software.games.exclude = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "guitarHero3" ];
    description = "Game launcher module ids to exclude from the default game library.";
  };

  options.software.games.syncRoot = lib.mkOption {
    type = lib.types.str;
    default = "/home/taylor/Games/synced";
    description = ''
      Local directory the roms Syncthing folder syncs selected games into on this
      host. May point at removable media (e.g. an SD card mount) — Syncthing's
      folder marker keeps that safe when the card is absent. Selected games launch
      from "<syncRoot>/<basePath>"; unselected ones launch from the CIFS library
      mount at ${cifsRoot} instead.
    '';
  };

  options.software.games.syncGames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "guitarHero3" ];
    description = ''
      Individual game entry ids to keep on this host's local disk (synced via the
      roms Syncthing share). Each must have a relative basePath. De-selecting a game
      and rebuilding deletes its local copy.
    '';
  };

  options.software.games.syncPlatforms = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "ps3" ];
    description = ''
      Whole platforms (first path segment of a basePath, e.g. "ps3", "pc") to keep
      on this host's local disk, or [ "*" ] to sync the entire library. Combined
      (union) with software.games.syncGames.
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

  options.software.games.steamSync.stopSteamDuringSync = lib.mkEnableOption ''
    stopping Steam while syncing non-Steam shortcuts and collections
  '';

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

          basePath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "pc/GH3";
            description = ''
              The game's location under the roms library root, e.g. "pc/GH3" (a
              directory holding the .exe for umu/Proton) or
              "ps3/Some Game (USA).iso" (the ISO for an emulator). A relative
              basePath is a library game: it launches from the CIFS mount
              (${cifsRoot}/<basePath>) or, when this host selects it via
              software.games.syncGames/syncPlatforms, from
              <syncRoot>/<basePath>, and it is eligible for local sync. An absolute
              path (/, ~, $HOME) marks a one-off launcher that never syncs.
              Required for umu and emulator runners; unused for native runners.
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

          lsfgVk.enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Whether to enable lsfg-vk for this game. Null inherits the global default.";
          };

          runner.umu = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  exe = lib.mkOption {
                    type = lib.types.str;
                    example = "GH3.exe";
                    description = "Path to the Windows executable, relative to the entry's basePath.";
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
            description = "Run this game through an emulator backend. The game path comes from the entry's basePath.";
          };
        };
      }
    );
    default = { };
    description = "Data-driven game launcher entries.";
  };

  config = lib.mkMerge [
    {
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
                entryCfg.runner.native != null || entryCfg.basePath != null;
              message = "software.games.entries.${entryName} must define basePath (umu and emulator runners locate the game via it).";
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
          assertion = entry != null && entry.basePath != null && isRelative entry.basePath;
          message = "software.games.syncGames entry \"${id}\" must exist in software.games.entries and define a relative (library) basePath.";
        }
      ) cfg.syncGames;

      software.games.manifest = gamesManifest;

      environment.systemPackages =
        (map (entryPackage: entryPackage.package) entryPackages)
        ++ lib.flatten (map (entryPackage: entryPackage.extraPackages) entryPackages);
    }

    # Only hosts that actually select games touch the Syncthing/prune machinery,
    # so the games module never hard-depends on my.syncthing where it is unused.
    (lib.mkIf hasSelection {
      my.syncthing.sharePaths.roms = cfg.syncRoot;
      my.syncthing.extraIgnores.roms = romsIgnores;

      # Delete local copies of de-selected games. Safe: the roms folder is
      # ignoreDelete, so this rm never propagates to the server, and the updated
      # .stignore stops Syncthing re-fetching. Re-runs whenever the selection
      # (managedFile) changes.
      systemd.services.game-local-prune = {
        description = "Prune de-selected local game copies under syncRoot";
        wantedBy = [ "multi-user.target" ];
        after = [ "syncthing.service" ];
        restartTriggers = [ managedFile ] ++ map pruneKeepFile excludeDirs;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          state_dir=/var/lib/game-local-sync
          mkdir -p "$state_dir"
          state="$state_dir/manifest"
          touch "$state"
          sync_root=${lib.escapeShellArg cfg.syncRoot}
          # Delete roots we synced last time that are no longer selected.
          while IFS= read -r p; do
            [ -n "$p" ] || continue
            if ! ${pkgs.gnugrep}/bin/grep -qxF -- "$p" ${managedFile}; then
              rm -rf -- "$sync_root/$p"
            fi
          done < "$state"
          # Also delete direct children that were fetched before the ignore rules
          # narrowed. For example, with only pc/GH3 selected, remove pc/Call of
          # Duty but keep pc/GH3.
          ${lib.concatMapStringsSep "\n" (
            d:
            let
              keepFile = pruneKeepFile d;
            in
            ''
              dir="$sync_root/${d}"
              if [ -d "$dir" ]; then
                for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
                  [ -e "$child" ] || continue
                  child_name="''${child##*/}"
                  child_rel="${d}/$child_name"
                  if ! ${pkgs.gnugrep}/bin/grep -qxF -- "$child_rel" ${keepFile}; then
                    rm -rf -- "$child"
                  fi
                done
              fi
            ''
          ) excludeDirs}
          cp ${managedFile} "$state"
        '';
      };
    })
  ];
}
