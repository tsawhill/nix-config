# Symlinks game data directories into the `gamesaves` Syncthing share, so saves
# and selected configs follow the user across hosts.
#
# A host opts in automatically when it participates in the gamesaves share
# (derived from osConfig). Each link has a stock local path and a path relative
# to the share root; set a link's `path` to null to skip it on a host.
{
  config,
  lib,
  osConfig,
  ...
}:
let
  cfg = config.my.gameSaveLinks;

  st = osConfig.my.syncthing or { };
  gamesavesPath = (st.resolvedPaths or { }).${cfg.share} or null;
  participates = (st.enable or false) && gamesavesPath != null;

  activeLinks = lib.mapAttrsToList (_: l: {
    src = l.path;
    target = "${gamesavesPath}/${l.sharePath}";
  }) (lib.filterAttrs (_: l: l.path != null) cfg.links);

  # Point src at target, but never clobber an existing real directory - that
  # would be the user's un-migrated data. Refresh a stale symlink in place.
  # The target is created too, so the link works before Syncthing pulls it.
  linkScript = l: ''
    src=${lib.escapeShellArg l.src}
    target=${lib.escapeShellArg l.target}
    run mkdir -p "$(dirname "$src")"
    if [ -L "$src" ] || [ ! -e "$src" ]; then
      run mkdir -p "$target"
      run ln -sfn "$target" "$src"
    else
      echo "game-save-links: $src exists and is not a symlink; leaving it alone (move its contents into $target to sync them)" >&2
    fi
  '';
in
{
  options.my.gameSaveLinks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = participates;
      defaultText = lib.literalExpression "host participates in the gamesaves share";
      description = "Symlink game data dirs into the gamesaves share. Defaults on when this host is a gamesaves member.";
    };

    share = lib.mkOption {
      type = lib.types.str;
      default = "gamesaves";
      description = "Syncthing share whose paths back the links.";
    };

    links = lib.mkOption {
      default = { };
      description = ''
        Game data-dir links. `path` is the stock on-disk directory replaced with
        a symlink into the share; null means no link (skipped). `sharePath` is
        relative to the configured share root.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Local data dir to symlink into the share, or null to skip.";
            };

            sharePath = lib.mkOption {
              type = lib.types.str;
              description = "Path inside the configured share root. Required when path is set.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = gamesavesPath != null;
        message = "my.gameSaveLinks is enabled but this host does not participate in the '${cfg.share}' Syncthing share.";
      }
    ];

    # Default link paths. mkDefault so a host can override or null any of them.
    my.gameSaveLinks.links = {
      RetroArch = {
        path = lib.mkDefault "${config.xdg.configHome}/retroarch";
        sharePath = lib.mkDefault "Emulators/RetroArch";
      };
      Dolphin = {
        path = lib.mkDefault "${config.home.homeDirectory}/.local/share/dolphin-emu";
        sharePath = lib.mkDefault "Emulators/Dolphin";
      };
      # Dolphin splits its data dir (above) from its config dir; the inis with
      # the controller binds live here, so it needs its own link.
      DolphinConfig = {
        path = lib.mkDefault "${config.xdg.configHome}/dolphin-emu";
        sharePath = lib.mkDefault "Emulators/DolphinConfig";
      };
      PCSX2 = {
        path = lib.mkDefault "${config.xdg.configHome}/PCSX2";
        sharePath = lib.mkDefault "Emulators/PCSX2";
      };
      RPCS3 = {
        path = lib.mkDefault "${config.xdg.configHome}/rpcs3";
        sharePath = lib.mkDefault "Emulators/RPCS3";
      };
      Ryujinx = {
        path = lib.mkDefault "${config.xdg.configHome}/Ryujinx";
        sharePath = lib.mkDefault "Emulators/Ryujinx";
      };
      runelite = {
        path = lib.mkDefault "${config.xdg.dataHome}/bolt-launcher/.runelite";
        sharePath = lib.mkDefault "runelite";
      };
      # Both channels (release/, nightly/) with their profiles, scores and settings.
      YARG = {
        path = lib.mkDefault "${config.xdg.configHome}/unity3d/YARC/YARG";
        sharePath = lib.mkDefault "YARG";
      };
      # Clone Hero keeps settings/custom content and scores in separate dirs.
      CloneHero = {
        path = lib.mkDefault "${config.home.homeDirectory}/.clonehero";
        sharePath = lib.mkDefault "CloneHero/data";
      };
      CloneHeroUnity = {
        path = lib.mkDefault "${config.xdg.configHome}/unity3d/srylain Inc_/Clone Hero";
        sharePath = lib.mkDefault "CloneHero/unity3d";
      };
      # DS: no stock PC path yet -> set my.gameSaveLinks.links.DS.{path,sharePath} per host to enable.
    };

    home.activation.gameSaveLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStringsSep "\n" linkScript activeLinks
    );
  };
}
