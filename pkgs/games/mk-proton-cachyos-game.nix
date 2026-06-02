{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
  umu-launcher,
  protonCachyos,
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
  # umu wants the Proton install directory (the one containing the `proton`
  # script), not the wrapper binary.
  protonPath = "${protonCachyos}/share/steam/compatibilitytools.d/proton-cachyos";
  umuRun = "${umu-launcher}/bin/umu-run";
  runCommand =
    if gamescopeArgs == null then
      ''
        exec ${umuRun} "$exe_path"
      ''
    else
      ''
        exec ${lib.getExe gamescope} ${lib.escapeShellArgs gamescopeArgs} -- \
          ${umuRun} "$exe_path"
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

      # Run Proton through umu (Steam Runtime "sniper" / pressure-vessel). Unlike
      # the steam-run FHS shim this provides a working 32-bit GPU driver stack,
      # which 32-bit titles need to enumerate the GPU.
      export GAMEID=0
      export PROTONPATH=${lib.escapeShellArg protonPath}
      export WINEPREFIX="$prefix_path"
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
