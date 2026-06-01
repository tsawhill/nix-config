{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
  steam-run,
  protonCachyos,
}:

{
  name,
  desktopName,
  exePath,
  prefixPath,
  gamescopeArgs ? null,
  env ? { },
}:
let
  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") env
  );
  runCommand =
    if gamescopeArgs == null then
      ''
        exec ${lib.getExe steam-run} ${lib.getExe protonCachyos} run "$exe_path"
      ''
    else
      ''
        exec ${lib.getExe gamescope} ${lib.escapeShellArgs gamescopeArgs} -- \
          ${lib.getExe steam-run} ${lib.getExe protonCachyos} run "$exe_path"
      '';

  launcher = writeShellApplication {
    inherit name;
    text = ''
      set -euo pipefail

      exe_path=${lib.escapeShellArg exePath}
      prefix_path=${lib.escapeShellArg prefixPath}

      case "$exe_path" in
        "~") exe_path="$HOME" ;;
        "~/"*) exe_path="$HOME/''${exe_path#~/}" ;;
      esac

      case "$prefix_path" in
        "~") prefix_path="$HOME" ;;
        "~/"*) prefix_path="$HOME/''${prefix_path#~/}" ;;
      esac

      game_dir="''${exe_path%/*}"
      if [ "$game_dir" = "$exe_path" ]; then
        game_dir="."
      fi

      cd "$game_dir"

      export STEAM_COMPAT_DATA_PATH="$prefix_path"
      export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
      export STEAM_COMPAT_INSTALL_PATH="$game_dir"
      export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam"
      ${envExports}

      ${runCommand}
    '';
  };

  desktopItem = makeDesktopItem {
    inherit name desktopName;
    exec = lib.getExe launcher;
    terminal = false;
    categories = [ "Game" ];
  };
in
symlinkJoin {
  name = "${name}-launcher";
  paths = [
    launcher
    desktopItem
  ];
}
