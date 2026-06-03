{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
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
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
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
    else if path == "$HOME" then
      "$HOME"
    else if lib.hasPrefix "$HOME/" path then
      "$HOME/${lib.escapeShellArg (lib.removePrefix "$HOME/" path)}"
    else
      lib.escapeShellArg path;
  effectiveEnv = env ++ lib.optionals lsfgVkEnable [ "DISABLE_LSFG=0" ];
  envExports = lib.concatStringsSep "\n" (
    map (assignment: "export ${lib.escapeShellArg assignment}") effectiveEnv
  );
  umuRun = "${umu-launcher}/bin/umu-run";

  resolutionLabel = resolution: "${toString resolution.width}x${toString resolution.height}";
  resolutionArgs =
    resolution:
    "-W ${toString resolution.width} -H ${toString resolution.height} -w ${toString resolution.width} -h ${toString resolution.height}";

  hasMultipleResolutions = builtins.length gamescopeResolutions > 1;
  entries =
    if gamescopeResolutions == [ ] then
      [
        {
          inherit name desktopName gamescopeArgs;
        }
      ]
    else
      map (
        resolution:
        let
          label = resolutionLabel resolution;
        in
        {
          name = name + lib.optionalString hasMultipleResolutions "-${label}";
          desktopName = desktopName + lib.optionalString hasMultipleResolutions " (${label})";
          gamescopeArgs =
            resolutionArgs resolution
            + lib.optionalString (gamescopeArgs != null) " ${gamescopeArgs}";
        }
      ) gamescopeResolutions;

  runCommand =
    entry:
    if entry.gamescopeArgs == null then
      ''
        exec ${umuRun} "$exe_path"
      ''
    else
      ''
        exec ${lib.getExe gamescope} ${entry.gamescopeArgs} -- \
          ${umuRun} "$exe_path"
      '';

  mkLauncher = entry: writeShellApplication {
    inherit (entry) name;
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

      ${runCommand entry}
    '';
  };

  mkDesktopItem = entry: launcher: makeDesktopItem {
    inherit (entry) name desktopName;
    exec = lib.getExe launcher;
    terminal = false;
    categories = [ "Game" ];
  };

  packages = lib.flatten (
    map (
      entry:
      let
        launcher = mkLauncher entry;
      in
      [
        launcher
        (mkDesktopItem entry launcher)
      ]
    ) entries
  );
in
symlinkJoin {
  name = "${name}-launcher";
  paths = packages;
}
