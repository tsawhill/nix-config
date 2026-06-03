{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  gamescope,
  coreutils,
  gnugrep,
  runtimeShell,
}:

{
  name,
  desktopName,
  runnerCommand,
  setupScript ? "",
  gamescopeMode ? "session",
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
  env ? [ ],
  lsfgVkEnable ? false,
}:
let
  effectiveEnv = env ++ lib.optionals lsfgVkEnable [ "DISABLE_LSFG=0" ];
  envExports = lib.concatStringsSep "\n" (
    map (assignment: "export ${lib.escapeShellArg assignment}") effectiveEnv
  );

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
    else if gamescopeMode == "direct" then
      ''
        exec ${lib.getExe gamescope} ${entry.gamescopeArgs} -- \
          ${runnerCommand}
      ''
    else
      ''
        env_file="$(mktemp -t ${entry.name}.gamescope-env.XXXXXX)"
        gamescope_pid=
        runner_status=0

        cleanup_gamescope() {
          if [ -n "$gamescope_pid" ] && kill -0 "$gamescope_pid" 2>/dev/null; then
            kill "$gamescope_pid" 2>/dev/null || true
            wait "$gamescope_pid" 2>/dev/null || true
          fi
          rm -f "$env_file"
        }
        trap cleanup_gamescope EXIT INT TERM

        ${lib.getExe gamescope} ${entry.gamescopeArgs} -- ${runtimeShell} -c '
          printf "%s\n%s\n%s\n" "$DISPLAY" "''${WAYLAND_DISPLAY:-}" "$$" > "$1"
          while :; do sleep 3600; done
        ' gamescope-session-keeper "$env_file" &
        gamescope_pid=$!

        for _ in $(seq 1 100); do
          if [ -s "$env_file" ]; then
            break
          fi
          sleep 0.1
        done

        if [ ! -s "$env_file" ]; then
          echo "gamescope did not publish a nested display" >&2
          exit 1
        fi

        {
          IFS= read -r nested_display
          IFS= read -r nested_wayland_display
          IFS= read -r keeper_pid
        } < "$env_file"

        if [ -n "$nested_wayland_display" ]; then
          env DISPLAY="$nested_display" WAYLAND_DISPLAY="$nested_wayland_display" ${runnerCommand} &
        else
          env -u WAYLAND_DISPLAY DISPLAY="$nested_display" ${runnerCommand} &
        fi
        runner_pid=$!
        wait "$runner_pid" || runner_status=$?

        has_gamescope_client() {
          local proc_env proc_pid
          for proc_env in /proc/[0-9]*/environ; do
            [ -r "$proc_env" ] || continue
            proc_pid="''${proc_env#/proc/}"
            proc_pid="''${proc_pid%/environ}"
            [ "$proc_pid" != "$keeper_pid" ] || continue

            if tr '\0' '\n' < "$proc_env" 2>/dev/null | grep -qx "DISPLAY=$nested_display"; then
              return 0
            fi
          done
          return 1
        }

        quiet_seconds=0
        while [ "$quiet_seconds" -lt 5 ]; do
          if has_gamescope_client; then
            quiet_seconds=0
          else
            quiet_seconds=$((quiet_seconds + 1))
          fi
          sleep 1
        done

        exit "$runner_status"
      '';

  mkLauncher = entry: writeShellApplication {
    inherit (entry) name;
    runtimeInputs = [
      coreutils
      gnugrep
    ];
    # SC2329: cleanup_gamescope is invoked indirectly via `trap`.
    # SC2016: the inner `${runtimeShell} -c '...'` expands these, not us.
    excludeShellChecks = [
      "SC2016"
      "SC2329"
    ];
    text = ''
      set -euo pipefail

      ${setupScript}
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
