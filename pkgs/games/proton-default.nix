{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  umu-launcher,
  protonPath,
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

  mkLauncher =
    {
      name,
      pressureVesselFilesystemsRw ? null,
    }:
    writeShellApplication {
      inherit name;
      text = ''
        set -euo pipefail

        if [ "$#" -lt 1 ]; then
          echo "Usage: ${name} path/to/program.exe [args...]" >&2
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
        ${lib.optionalString (pressureVesselFilesystemsRw != null) ''
          export PRESSURE_VESSEL_FILESYSTEMS_RW=${lib.escapeShellArg pressureVesselFilesystemsRw}
        ''}

        exec ${umu-launcher}/bin/umu-run "$exe_name" "$@"
      '';
    };

  mkDesktopItem =
    {
      name,
      desktopName,
      launcher,
    }:
    makeDesktopItem {
      inherit name desktopName;
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

  launcher = mkLauncher { name = "proton"; };
  diskAccessLauncher = mkLauncher {
    name = "proton-disk-access";
    # pressure-vessel reserves its runtime paths and will not expose `/`
    # directly. Sharing `/mnt` covers every Incus disk passthrough; the user's
    # home is already shared read/write by UMU. Unix permissions still apply.
    pressureVesselFilesystemsRw = "/mnt";
  };

  desktopItem = mkDesktopItem {
    name = "proton-open-with";
    desktopName = "Proton";
    inherit launcher;
  };
  diskAccessDesktopItem = mkDesktopItem {
    name = "proton-disk-access-open-with";
    desktopName = "Proton (w/ disk access)";
    launcher = diskAccessLauncher;
  };
in
symlinkJoin {
  name = "proton-default";
  paths = [
    launcher
    desktopItem
    diskAccessLauncher
    diskAccessDesktopItem
  ];
}
