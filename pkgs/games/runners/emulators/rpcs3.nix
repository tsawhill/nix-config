{
  lib,
  rpcs3,
}:

{
  gamePath,
  args ? [ ],
}:
let
  defaultGameDirectory = "$HOME/Games/roms/ps3";

  resolvedGamePath =
    if
      lib.hasPrefix "/" gamePath
      || lib.hasPrefix "~/" gamePath
      || lib.hasPrefix "$HOME/" gamePath
      || gamePath == "~"
      || gamePath == "$HOME"
    then
      gamePath
    else
      "${defaultGameDirectory}/${gamePath}";

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

  argsString = lib.escapeShellArgs args;
in
{
  setupScript = ''
    game_path=${shellPath resolvedGamePath}
  '';

  runnerCommand =
    "${lib.getExe rpcs3} --no-gui \"$game_path\""
    + lib.optionalString (argsString != "") " ${argsString}";
}
