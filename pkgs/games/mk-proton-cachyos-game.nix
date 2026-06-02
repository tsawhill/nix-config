{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
  steam-run,
  protonCachyos,
  freetype,
  fontconfig,
  pkgsi686Linux,
}:

{
  name,
  desktopName,
  exePath,
  prefixPath,
  gamescopeArgs ? null,
  env ? [ ],
  lsfgVkEnable ? false,
}:
let
  shellPath =
    path:
    if path == "~" then
      "$HOME"
    else if lib.hasPrefix "~/" path then
      "$HOME/${lib.escapeShellArg (lib.removePrefix "~/" path)}"
    else
      lib.escapeShellArg path;
  effectiveEnv = env ++ lib.optionals lsfgVkEnable [ "DISABLE_LSFG=0" ];
  envExports = lib.concatStringsSep "\n" (
    map (assignment: "export ${lib.escapeShellArg assignment}") effectiveEnv
  );
  runtimeLibraryPath = lib.makeLibraryPath [
    freetype
    fontconfig
    pkgsi686Linux.freetype
    pkgsi686Linux.fontconfig
  ];
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

      exe_path=${shellPath exePath}
      prefix_path=${shellPath prefixPath}

      game_dir="''${exe_path%/*}"
      if [ "$game_dir" = "$exe_path" ]; then
        game_dir="."
      fi

      cd "$game_dir"

      export STEAM_COMPAT_DATA_PATH="$prefix_path"
      export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
      export STEAM_COMPAT_INSTALL_PATH="$game_dir"
      export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam"
      export LD_LIBRARY_PATH=${lib.escapeShellArg runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
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
