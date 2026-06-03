{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
}:

{
  name,
  desktopName,
  runnerCommand,
  setupScript ? "",
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
  env ? [ ],
  lsfgVkEnable ? false,
}:
let
  envExports = lib.concatStringsSep "\n" (
    map (assignment: "export ${lib.escapeShellArg assignment}") env
  );
  # The lsfg-vk implicit layer is gated by disable_environment = { DISABLE_LSFG = "1"; }.
  # The Vulkan loader disables an implicit layer whenever that variable is
  # *defined at all* — it never compares the value — so exporting DISABLE_LSFG=0
  # still disables it. The system-wide default defines DISABLE_LSFG to keep lsfg
  # off everywhere; to actually enable it for this launcher we must unset it.
  lsfgSetup = lib.optionalString lsfgVkEnable "unset DISABLE_LSFG";

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
        exec ${runnerCommand}
      ''
    else
      ''
        exec ${lib.getExe gamescope} ${entry.gamescopeArgs} -- \
          ${runnerCommand}
      '';

  mkLauncher = entry: writeShellApplication {
    inherit (entry) name;
    text = ''
      set -euo pipefail

      ${setupScript}
      ${envExports}
      ${lsfgSetup}

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
