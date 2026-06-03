{
  lib,
  umu-launcher,
}:

{
  exePath,
  prefixPath ? "$HOME/Games/saves/wine/default",
  protonPath,
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
in
{
  setupScript = ''
    exe_path=${shellPath exePath}
    prefix_path=${shellPath prefixPath}

    game_dir="''${exe_path%/*}"
    if [ "$game_dir" = "$exe_path" ]; then
      game_dir="."
    fi

    cd "$game_dir"

    export GAMEID=0
    export PROTONPATH=${lib.escapeShellArg protonPath}
    export WINEPREFIX="$prefix_path"
  '';
  runnerCommand = ''${umu-launcher}/bin/umu-run "$exe_path"'';
}
