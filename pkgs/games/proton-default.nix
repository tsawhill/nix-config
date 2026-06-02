{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  umu-launcher,
  protonPath ? "GE-Proton",
  prefixPath ? "$HOME/Games/saves/wine/default",
}:

let
  shellPath =
    path:
    if path == "~" then
      "$HOME"
    else if lib.hasPrefix "~/" path then
      "$HOME/${lib.escapeShellArg (lib.removePrefix "~/" path)}"
    else if path == "$HOME" then
      "$HOME"
    else if lib.hasPrefix "$HOME/" path then
      "$HOME/${lib.escapeShellArg (lib.removePrefix "$HOME/" path)}"
    else
      lib.escapeShellArg path;

  launcher = writeShellApplication {
    name = "proton";
    text = ''
      set -euo pipefail

      if [ "$#" -lt 1 ]; then
        echo "Usage: proton path/to/program.exe [args...]" >&2
        exit 2
      fi

      exe_path=$1
      shift
      exe_name="''${exe_path##*/}"

      prefix_path=${shellPath prefixPath}
      game_dir="''${exe_path%/*}"
      if [ "$game_dir" = "$exe_path" ]; then
        game_dir="."
      fi

      cd "$game_dir"

      export GAMEID=0
      export PROTONPATH=${lib.escapeShellArg protonPath}
      export WINEPREFIX="$prefix_path"

      exec ${umu-launcher}/bin/umu-run "$exe_name" "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "proton-open-with";
    desktopName = "Proton";
    exec = "${lib.getExe launcher} %f";
    terminal = false;
    noDisplay = true;
    categories = [ "Game" ];
    mimeTypes = [
      "application/x-ms-dos-executable"
      "application/x-msdownload"
      "application/vnd.microsoft.portable-executable"
    ];
  };
in
symlinkJoin {
  name = "proton-default";
  paths = [
    launcher
    desktopItem
  ];
}
