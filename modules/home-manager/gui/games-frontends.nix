{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

# Surfaces the NixOS software.games.* library in couch frontends, grouped by
# platform category (Proton / PS3 / GameCube-Wii / ...). The game list comes
# from osConfig.software.games.manifest (set by modules/software/games), so new
# games appear here automatically with no per-frontend edits.
let
  games = osConfig.software.games.manifest or [ ];

  home = config.home.homeDirectory;
  # Per-game art lives here; shared by Pegasus (assets.*) and any manual fetch.
  artBase = "${home}/Games/art";
  # Launchers are installed system-wide, so each command resolves here.
  binDir = "/run/current-system/sw/bin";

  categories = lib.unique (map (g: g.category) games);
  catGames = c: lib.filter (g: g.category == c) games;
  slug = s: lib.toLower (lib.replaceStrings [ " " "/" ] [ "-" "-" ] s);

  # ---------------------------------------------------------------------------
  # Pegasus (declarative, gamepad-native, non-Steam)
  # ---------------------------------------------------------------------------
  pegasusGameDir = "${config.xdg.dataHome}/pegasus-games";
  pegasusConfigDir = "${config.xdg.configHome}/pegasus-frontend";

  # Pegasus ships with no theme; the bare fallback UI can't navigate multiple
  # collections (everything looks lumped under the first one). gameOS is a
  # polished, collection-aware theme. Installed declaratively; selected via the
  # seeded settings.txt below.
  gameOsTheme = pkgs.fetchgit {
    url = "https://github.com/PlayingKarrde/gameOS";
    rev = "7a5a5223ff7371d0747a7c5d3a3b8f2f5e36b4f2";
    sha256 = "1mwrk8dk6rbr72nr32bnn524agjq01x1fyih1yxm7m5h8rxlh6hh";
  };

  # Seeded only if the user has no settings.txt yet, so Pegasus stays free to
  # rewrite its own settings afterward. Selects gameOS and fullscreen.
  pegasusSettingsSeed = pkgs.writeText "pegasus-settings.txt" ''
    general.fullscreen: true
    general.theme: ${pegasusConfigDir}/themes/gameOS
  '';

  # ---------------------------------------------------------------------------
  # Box art: fetch cover / logo / background from SteamGridDB into ~/Games/art/<id>/.
  # Needs a (free) SteamGridDB API key — read from $STEAMGRIDDB_API_KEY or the
  # sops secret at /run/secrets/steamgriddb_api_key. Run `fetch-game-art`
  # (add --force to refetch existing). No good keyless art source exists for
  # non-Steam games, so this is the automated alternative to manual files.
  # ---------------------------------------------------------------------------
  artGamesJson = pkgs.writeText "game-art-games.json" (
    builtins.toJSON (map (g: { inherit (g) id name; }) games)
  );

  fetchGameArt = pkgs.writeShellApplication {
    name = "fetch-game-art";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      set -euo pipefail
      art_base=${lib.escapeShellArg artBase}
      games=${artGamesJson}

      key="''${STEAMGRIDDB_API_KEY:-}"
      if [ -z "$key" ] && [ -r /run/secrets/steamgriddb_api_key ]; then
        key="$(cat /run/secrets/steamgriddb_api_key)"
      fi
      if [ -z "$key" ]; then
        echo "No SteamGridDB API key. Set STEAMGRIDDB_API_KEY or enable the sops secret." >&2
        exit 1
      fi

      force=0
      if [ "''${1:-}" = "--force" ]; then force=1; fi

      api() { curl -fsSL -H "Authorization: Bearer $key" "$@"; }
      first_url() { jq -r '.data[0].url // empty'; }

      while read -r g; do
        id="$(jq -r '.id' <<<"$g")"
        name="$(jq -r '.name' <<<"$g")"
        # Drop a trailing platform suffix like " (PS3)" for a cleaner search.
        term="$(sed -E 's/ *\([^)]*\)$//' <<<"$name")"
        dir="$art_base/$id"

        if [ -f "$dir/boxFront.png" ] && [ "$force" -eq 0 ]; then
          echo "skip (have art): $name"
          continue
        fi

        enc="$(jq -rn --arg s "$term" '$s|@uri')"
        sid="$(api "https://www.steamgriddb.com/api/v2/search/autocomplete/$enc" \
          | jq -r '.data[0].id // empty')" || sid=""
        if [ -z "$sid" ]; then
          echo "no SteamGridDB match: $name" >&2
          continue
        fi

        mkdir -p "$dir"
        box="$(api "https://www.steamgriddb.com/api/v2/grids/game/$sid?dimensions=600x900&types=static&limit=1" | first_url)" || box=""
        if [ -n "$box" ]; then curl -fsSL -o "$dir/boxFront.png" "$box"; fi
        logo="$(api "https://www.steamgriddb.com/api/v2/logos/game/$sid?limit=1" | first_url)" || logo=""
        if [ -n "$logo" ]; then curl -fsSL -o "$dir/logo.png" "$logo"; fi
        hero="$(api "https://www.steamgriddb.com/api/v2/heroes/game/$sid?limit=1" | first_url)" || hero=""
        if [ -n "$hero" ]; then curl -fsSL -o "$dir/background.png" "$hero"; fi
        echo "art: $name"
      done < <(jq -c '.[]' "$games")

      echo "Done. Restart Pegasus to see new art."
    '';
  };

  gameBlock = g: ''
    game: ${g.name}
    file: launchers/${g.command}
    launch: ${binDir}/${g.command}
    assets.boxFront: ${artBase}/${g.id}/boxFront.png
    assets.logo: ${artBase}/${g.id}/logo.png
    assets.background: ${artBase}/${g.id}/background.png
  '';

  # Canonical Pegasus layout: one directory per collection, each holding a
  # single-collection metadata file. Multiple collections in one file is
  # ambiguous and gameOS misgroups it (PS3 titles bleeding into the first
  # collection), so keep each category isolated in its own game dir.
  collectionMetadata =
    c:
    "collection: ${c}\nshortname: ${slug c}\n\n" + lib.concatMapStringsSep "\n" gameBlock (catGames c);

  pegasusMetadataFiles = lib.listToAttrs (
    map (c: {
      name = "pegasus-games/${slug c}/metadata.pegasus.txt";
      value.text = collectionMetadata c;
    }) categories
  );

  # Pegasus needs an on-disk file per game as a stable identity; empty markers
  # under <collection>/launchers/ satisfy that while the real launch is the
  # `launch:` command.
  pegasusMarkerFiles = lib.listToAttrs (
    map (g: {
      name = "pegasus-games/${slug g.category}/launchers/${g.command}";
      value.text = "";
    }) games
  );

  # Register each collection directory with Pegasus (one per line).
  pegasusGameDirs = lib.concatMapStringsSep "\n" (c: "${pegasusGameDir}/${slug c}") categories + "\n";

  # ---------------------------------------------------------------------------
  # Steam non-Steam shortcuts (categorized), written directly into shortcuts.vdf
  # by sync-steam-shortcuts. Each game's category becomes a Steam tag, and the
  # SteamGridDB art under ~/Games/art/<id>/ is copied into the account grid dir.
  # ---------------------------------------------------------------------------
  steamGamesJson = pkgs.writeText "steam-games.json" (
    builtins.toJSON (
      map (g: { inherit (g) id name command category; }) games
    )
  );

  syncSteamShortcuts = pkgs.writeShellApplication {
    name = "sync-steam-shortcuts";
    runtimeInputs = [
      (pkgs.python3.withPackages (p: [ p.vdf ]))
      pkgs.procps # pgrep, to warn when Steam is running
    ];
    text = ''
      exec python3 ${./sync-steam-shortcuts.py} ${steamGamesJson} ${lib.escapeShellArg artBase} ${binDir}
    '';
  };
in
{
  config = lib.mkIf (games != [ ]) {
    home.packages = [
      fetchGameArt
      syncSteamShortcuts
    ];

    systemd.user.services.fetch-game-art = {
      Unit.Description = "Fetch game box art from SteamGridDB into ~/Games/art";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe fetchGameArt;
      };
    };

    # Sync non-Steam shortcuts after each rebuild. The script skips safely if
    # Steam is already running, because Steam rewrites shortcuts.vdf on exit.
    systemd.user.services.sync-steam-shortcuts = {
      Unit = {
        Description = "Sync software.games.* into Steam as non-Steam shortcuts";
        After = [ "fetch-game-art.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe syncSteamShortcuts;
      };
    };

    # Refresh art and Steam shortcuts after each home-manager activation (i.e.
    # every rebuild). Both skip work that's already done, so they're cheap no-ops
    # when nothing changed. --no-block so activation never waits.
    home.activation.gameFrontendsSync = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      run ${pkgs.systemd}/bin/systemctl --user start --no-block fetch-game-art.service || true
      run ${pkgs.systemd}/bin/systemctl --user start --no-block sync-steam-shortcuts.service || true
    '';

    xdg.dataFile = pegasusMetadataFiles // pegasusMarkerFiles;

    # Register each collection directory with Pegasus (one dir per line).
    xdg.configFile."pegasus-frontend/game_dirs.txt".text = pegasusGameDirs;

    # Install the gameOS theme (read-only; Pegasus only reads themes).
    xdg.configFile."pegasus-frontend/themes/gameOS".source = gameOsTheme;

    # Seed settings.txt once so gameOS is pre-selected; left writable for Pegasus.
    home.activation.pegasusSettingsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="${pegasusConfigDir}/settings.txt"
      if [ ! -e "$settings" ]; then
        run mkdir -p "$(dirname "$settings")"
        run install -m644 ${pegasusSettingsSeed} "$settings"
      fi
    '';
  };
}
