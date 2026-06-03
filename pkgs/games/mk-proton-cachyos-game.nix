{
  lib,
  callPackage,
  umu-launcher,
}:

{
  name,
  desktopName,
  exePath,
  prefixPath ? "$HOME/Games/saves/wine/default",
  # umu PROTONPATH: either an absolute path to a Proton install, or a umu
  # codename like "GE-Proton" that umu downloads and manages itself.
  protonPath,
  gamescopeMode ? "session",
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
  env ? [ ],
  lsfgVkEnable ? false,
}:
let
  mkGameLauncher = callPackage ./mk-game-launcher.nix { };
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
  umuRun = "${umu-launcher}/bin/umu-run";
  setupScript = ''
    exe_path=${shellPath exePath}
    prefix_path=${shellPath prefixPath}

    game_dir="''${exe_path%/*}"
    if [ "$game_dir" = "$exe_path" ]; then
      game_dir="."
    fi

    cd "$game_dir"

    # Run Proton through umu (Steam Runtime "sniper" / pressure-vessel). Unlike
    # the steam-run FHS shim this provides a working 32-bit GPU driver stack,
    # which 32-bit titles need to enumerate the GPU.
    export GAMEID=0
    export PROTONPATH=${lib.escapeShellArg protonPath}
    export WINEPREFIX="$prefix_path"
  '';
in
mkGameLauncher {
  inherit
    name
    desktopName
    setupScript
    gamescopeMode
    gamescopeArgs
    gamescopeResolutions
    env
    lsfgVkEnable
    ;
  runnerCommand = ''${umuRun} "$exe_path"'';
}
