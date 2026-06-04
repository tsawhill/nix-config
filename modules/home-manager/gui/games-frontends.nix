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

  gameBlock = g: ''
    game: ${g.name}
    file: launchers/${g.command}
    launch: ${binDir}/${g.command}
    assets.boxFront: ${artBase}/${g.id}/boxFront.png
    assets.logo: ${artBase}/${g.id}/logo.png
  '';
  collectionBlock =
    c:
    "collection: ${c}\nshortname: ${slug c}\n\n" + lib.concatMapStringsSep "\n" gameBlock (catGames c);
  pegasusMetadata = lib.concatMapStringsSep "\n" collectionBlock categories + "\n";

  # Pegasus needs an on-disk file per game as a stable identity; empty markers
  # under launchers/ satisfy that while the real launch is the `launch:` command.
  markerFiles = lib.listToAttrs (
    map (g: {
      name = "pegasus-games/launchers/${g.command}";
      value = {
        text = "";
      };
    }) games
  );

  # ---------------------------------------------------------------------------
  # Steam ROM Manager manifests (categorized non-Steam shortcuts)
  # One manifest dir per category; SRM imports each as a "Manual" parser whose
  # Steam Category becomes the platform. SRM owns its userConfigurations.json
  # (it rewrites it), so only the manifests are managed declaratively here.
  # ---------------------------------------------------------------------------
  srmEntry = g: {
    title = g.name;
    target = "${binDir}/${g.command}";
    startIn = binDir;
    launchOptions = "";
  };
  srmManifestFiles = lib.listToAttrs (
    map (c: {
      name = "game-frontends/srm/${slug c}/manifest.json";
      value = {
        text = builtins.toJSON (map srmEntry (catGames c));
      };
    }) categories
  );

  srmReadme = ''
    Steam ROM Manager — categorized non-Steam shortcuts
    ===================================================
    These manifests are generated from software.games.entries (NixOS) and stay
    in sync on every rebuild. Each subdirectory below is one Steam category.

    One-time setup in `steam-rom-manager` (GUI): add a "Manual" parser per
    category, set its Steam Category, and point its manifests directory at the
    matching folder:

    ${lib.concatMapStringsSep "\n" (
      c: "  • Steam Category: ${c}\n    Manifests dir:   ${config.xdg.dataHome}/game-frontends/srm/${slug c}"
    ) categories}

    Enable the SteamGridDB image provider for box art, then Preview → Save to
    Steam and restart Steam. Re-run "Save to Steam" after adding/removing games;
    the manifests update themselves.
  '';
in
{
  config = lib.mkIf (games != [ ]) {
    xdg.dataFile = markerFiles // srmManifestFiles // {
      "pegasus-games/metadata.pegasus.txt".text = pegasusMetadata;
      "game-frontends/srm/README.txt".text = srmReadme;
    };

    # Register the generated collection with Pegasus (one dir per line).
    xdg.configFile."pegasus-frontend/game_dirs.txt".text = "${pegasusGameDir}\n";

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
