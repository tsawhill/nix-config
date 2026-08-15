{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  coreutils,
  gamescope,
  util-linux,
}:

{
  name,
  desktopName,
  runnerCommand,
  setupScript ? "",
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
  env ? [ ],
  lsfgVkConfig ? null,
  lsfgVkEnable ? false,
  lsfgVkProcess ? name,
  networkEnable ? false,
}:
let
  envExports = lib.concatStringsSep "\n" (
    map (assignment: "export ${lib.escapeShellArg assignment}") env
  );
  # The lsfg-vk implicit layer is gated by disable_environment = { DISABLE_LSFG = "1"; }.
  # The Vulkan loader disables an implicit layer whenever that variable is
  # *defined at all* — it never compares the value — so exporting DISABLE_LSFG=0
  # still disables it. The system-wide default defines DISABLE_LSFG to keep lsfg
  # off everywhere; to actually enable it for the game process we must unset it.
  #
  # Use an explicit profile identity instead of relying on the Vulkan process
  # name. This works for Proton launchers and also lets individual emulated games
  # have distinct LSFG profiles even though they share an emulator executable.
  # LSFG_CONFIG selects the immutable Nix-generated profile set without taking
  # ownership of the user's normal, manually editable config file.
  lsfgSetup = lib.optionalString lsfgVkEnable ''
    export DISABLE_LSFG=1
    export LSFG_CONFIG=${lib.escapeShellArg lsfgVkConfig}
    export LSFG_PROCESS=${lib.escapeShellArg lsfgVkProcess}
  '';

  # Enable lsfg-vk only for the game runner. In particular, keep the implicit
  # layer disabled while gamescope creates its own Vulkan instance and device.
  gameCommand =
    lib.optionalString lsfgVkEnable "${lib.getExe' coreutils "env"} -u DISABLE_LSFG " + runnerCommand;

  # Games are offline by default. A user namespace lets an unprivileged caller
  # create the network namespace, while mapping the caller to the same UID/GID
  # avoids making Wine/Proton believe it is running as root.
  isolatedGameCommand =
    if networkEnable then
      gameCommand
    else
      "${lib.getExe' util-linux "unshare"} --map-current-user --net -- ${gameCommand}";

  resolutionLabel = resolution: "${toString resolution.width}x${toString resolution.height}";
  resolutionArgs =
    resolution:
    let
      scale = resolution.scale or 1.0;
      gameWidth = builtins.floor (resolution.width * scale);
      gameHeight = builtins.floor (resolution.height * scale);
    in
    "-W ${toString resolution.width} -H ${toString resolution.height} -w ${toString gameWidth} -h ${toString gameHeight}"
    + lib.optionalString (resolution.refresh != null) " -r ${toString resolution.refresh}";

  entries = [
    {
      inherit name desktopName;
      gamescopeArgs = null;
    }
  ]
  ++ map (
    resolution:
    let
      label = resolutionLabel resolution;
    in
    {
      name = "${name}-${label}";
      desktopName = "${desktopName} (${label})";
      gamescopeArgs =
        resolutionArgs resolution + lib.optionalString (gamescopeArgs != null) " ${gamescopeArgs}";
    }
  ) gamescopeResolutions;

  runCommand =
    entry:
    if entry.gamescopeArgs == null then
      ''
        exec ${isolatedGameCommand}
      ''
    else
      ''
        exec ${lib.getExe gamescope} ${entry.gamescopeArgs} -- \
          ${isolatedGameCommand}
      '';

  mkLauncher =
    entry:
    writeShellApplication {
      inherit (entry) name;
      text = ''
        set -euo pipefail

        ${setupScript}
        ${envExports}
        ${lsfgSetup}

        ${runCommand entry}
      '';
    };

  mkDesktopItem =
    entry: launcher:
    makeDesktopItem {
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
