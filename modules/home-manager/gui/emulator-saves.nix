# Symlinks each emulator's stock data directory into the `gamesaves` Syncthing
# share, so configs + saves follow the user across hosts.
#
# A host opts in automatically when it participates in the gamesaves share
# (derived from osConfig). Each emulator has a default link path; override a
# link's `path` per machine, or leave it null (the default for emulators with no
# stock PC path, e.g. DS) to skip that link entirely.
{
  config,
  lib,
  osConfig,
  ...
}:
let
  cfg = config.my.emulatorSaves;

  st = osConfig.my.syncthing or { };
  gamesavesPath = (st.resolvedPaths or { }).${cfg.share} or null;
  participates = (st.enable or false) && gamesavesPath != null;

  # Links with a concrete path -> { name, src, target }.
  activeLinks = lib.mapAttrsToList (name: l: {
    src = l.path;
    target = "${gamesavesPath}/Emulators/${name}";
  }) (lib.filterAttrs (_: l: l.path != null) cfg.links);

  # Point src at target, but never clobber an existing real directory — that
  # would be the user's un-migrated data. Refresh a stale symlink in place.
  linkScript = l: ''
    src=${lib.escapeShellArg l.src}
    target=${lib.escapeShellArg l.target}
    run mkdir -p "$(dirname "$src")"
    if [ -L "$src" ]; then
      run ln -sfn "$target" "$src"
    elif [ ! -e "$src" ]; then
      run ln -s "$target" "$src"
    else
      echo "emulator-saves: $src exists and is not a symlink; leaving it alone (move its contents into $target to sync them)" >&2
    fi
  '';
in
{
  options.my.emulatorSaves = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = participates;
      defaultText = lib.literalExpression "host participates in the gamesaves share";
      description = "Symlink emulator data dirs into the gamesaves share. Defaults on when this host is a gamesaves member.";
    };

    share = lib.mkOption {
      type = lib.types.str;
      default = "gamesaves";
      description = "Syncthing share whose Emulators/<name> dirs back the links.";
    };

    links = lib.mkOption {
      default = { };
      description = ''
        Emulator data-dir links. The attribute name is the folder under
        `<gamesaves>/Emulators/`. `path` is the stock on-disk directory replaced
        with a symlink into that folder; null means no link (skipped).
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.path = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Local data dir to symlink into the share, or null to skip.";
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = gamesavesPath != null;
        message = "my.emulatorSaves is enabled but this host does not participate in the '${cfg.share}' Syncthing share.";
      }
    ];

    # Default link paths. mkDefault so a host can override or null any of them.
    my.emulatorSaves.links = {
      RetroArch.path = lib.mkDefault "${config.xdg.configHome}/retroarch";
      Dolphin.path = lib.mkDefault "${config.home.homeDirectory}/.local/share/dolphin-emu";
      PCSX2.path = lib.mkDefault "${config.xdg.configHome}/PCSX2";
      RPCS3.path = lib.mkDefault "${config.xdg.configHome}/rpcs3";
      # DS: no stock PC path yet -> set my.emulatorSaves.links.DS.path per host to enable.
    };

    home.activation.emulatorSaveLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStringsSep "\n" linkScript activeLinks
    );
  };
}
