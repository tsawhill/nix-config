# Video wallpapers played by mpvpaper, looped or rotated per monitor.
#
# Where to find videos (free MP4 loops):
#   - MotionBGs           https://motionbgs.com/           (best: lots of 4K, sane file sizes)
#   - MoeWalls            https://moewalls.com/
#   - Wallpaper Waifu     https://wallpaperwaifu.com/
#   - DesktopHut          https://www.desktophut.com/
#   - MyLiveWallpapers    https://mylivewallpapers.com/
#   - Pexels Videos       https://www.pexels.com/videos/   (stock footage: rain, cities, nature)
#   - Pixabay Videos      https://pixabay.com/videos/
#
# Adding videos:
#   1. Copy the MP4s into wallpapers/ in the repo on build-nix (git-ignored).
#   2. Run `wallpapers-sync` on build-nix. It renames files to Nix-safe names
#      (spaces etc. become -), adds them to the Nix store, keeps them from being
#      garbage collected, and updates wallpapers/manifest.json.
#   3. Deploy the hosts. Monitors without a `videos` list rotate through every
#      synced video; list names in `videos` to pick specific ones.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.my.hypr.wallpapers;

  # Videos stay out of git: wallpapers-sync on build-nix adds them to its store
  # and records their hashes here, and requireFile picks them up from there.
  manifestFile = ../../../../wallpapers/manifest.json;
  manifest = if builtins.pathExists manifestFile then lib.importJSON manifestFile else { };

  videosFor = monCfg: if monCfg.videos == null then lib.attrNames manifest else monCfg.videos;
  activeMonitors = lib.filterAttrs (_: monCfg: videosFor monCfg != [ ]) cfg.monitors;

  video =
    name:
    if manifest ? ${name} then
      pkgs.requireFile {
        inherit name;
        sha256 = manifest.${name};
        message = "${name} is not in the Nix store; run wallpapers-sync on build-nix.";
      }
    else
      throw "Wallpaper ${name} is not in wallpapers/manifest.json; put it in wallpapers/ on build-nix and run wallpapers-sync.";

  # Match argv[0] only: Steam's runtime helpers carry gamescope's Vulkan layer path in their args.
  disableAppsCheck =
    if cfg.disableApps == [ ] then
      "false"
    else
      lib.concatStringsSep " || " (
        map (
          app:
          "${pkgs.procps}/bin/pgrep -f ${lib.escapeShellArg "^([^ ]*/)?${lib.escapeRegex app}( |$)"} > /dev/null 2>&1"
        ) cfg.disableApps
      );

  mkWallpaperService =
    monitor: monCfg:
    let
      videos = map video (videosFor monCfg);
      # A single video just loops; restarting it every interval would only flicker.
      interval = if lib.length videos == 1 then "infinity" else monCfg.rotateInterval;

      mpvOptions = lib.concatStringsSep " " (
        [
          "loop-file=inf"
          "hwdec=auto-safe"
          "quiet" # No status line spamming the journal
        ]
        ++ {
          fill = [ "panscan=1.0" ];
          fit = [ ];
          stretch = [ "keepaspect=no" ];
        }
        .${monCfg.scaling}
        ++ (if monCfg.audio then [ "volume=${toString monCfg.volume}" ] else [ "no-audio" ])
      );

      rotationScript = pkgs.writeShellScript "wallpaper-${monitor}" ''
        VIDEOS=(${lib.escapeShellArgs videos})
        # Videos mpvpaper failed on this session; skipped until all have.
        declare -A FAILED=()
        LAST=

        trap 'kill $PLAYER_PID $SLEEP_PID 2>/dev/null; exit' SIGTERM SIGINT

        while true; do
          # Stay off while any disable-app is running
          while ${disableAppsCheck}; do
            sleep 1
          done

          CANDIDATES=()
          for V in "''${VIDEOS[@]}"; do
            [ -z "''${FAILED[$V]}" ] && [ "$V" != "$LAST" ] && CANDIDATES+=("$V")
          done
          # Repeat the last video if it is the only one left.
          if [ ''${#CANDIDATES[@]} -eq 0 ] && [ -n "$LAST" ] && [ -z "''${FAILED[$LAST]}" ]; then
            CANDIDATES=("$LAST")
          fi
          if [ ''${#CANDIDATES[@]} -eq 0 ]; then
            echo "Every wallpaper failed; retrying all in 60s" >&2
            sleep 60
            FAILED=()
            LAST=
            continue
          fi

          VIDEO=''${CANDIDATES[$(( RANDOM % ''${#CANDIDATES[@]} ))]}
          LAST=$VIDEO

          ${lib.getExe pkgs.mpvpaper} -p \
            -o ${lib.escapeShellArg mpvOptions} \
            ${lib.escapeShellArg monitor} "$VIDEO" &
          PLAYER_PID=$!

          # Run rotation sleep in background so we can interrupt it
          sleep ${lib.escapeShellArg interval} &
          SLEEP_PID=$!

          # Wait until the interval ends, a disable-app starts, or mpvpaper dies
          while kill -0 $SLEEP_PID 2>/dev/null; do
            if ${disableAppsCheck}; then
              kill $SLEEP_PID 2>/dev/null
              kill $PLAYER_PID 2>/dev/null
              wait $PLAYER_PID 2>/dev/null
              PLAYER_PID=
              break
            fi
            if ! kill -0 $PLAYER_PID 2>/dev/null; then
              echo "$VIDEO exited early; skipping it this session" >&2
              FAILED[$VIDEO]=1
              kill $SLEEP_PID 2>/dev/null
              PLAYER_PID=
              break
            fi
            sleep 5
          done

          if [ -n "$PLAYER_PID" ]; then
            kill $PLAYER_PID 2>/dev/null
            wait $PLAYER_PID 2>/dev/null
          fi
        done
      '';
    in
    {
      Unit = {
        Description = "Video wallpaper rotation for ${monitor}";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${rotationScript}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };
in
{
  options.my.hypr.wallpapers = {
    enable = lib.mkEnableOption "mpvpaper video wallpapers with per-monitor rotation";

    disableApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "gamescope" ];
      description = "Program names that stop all wallpapers while running, matched against the basename of each process's argv[0].";
    };

    monitors = lib.mkOption {
      default = { };
      description = "Per-monitor wallpaper configuration, keyed by monitor name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            videos = lib.mkOption {
              type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
              default = null;
              description = "File names in the repo's wallpapers/ directory, as renamed by wallpapers-sync; more than one rotates. Null (the default) rotates every video in wallpapers/manifest.json.";
            };

            rotateInterval = lib.mkOption {
              type = lib.types.str;
              default = "10m";
              description = "How long each video is shown before switching. Accepts sleep(1) units: 30m, 1h, 6h, etc.";
            };

            scaling = lib.mkOption {
              type = lib.types.enum [
                "fill"
                "fit"
                "stretch"
              ];
              default = "fill";
              description = "fill crops to cover the output, fit letterboxes, stretch ignores aspect ratio.";
            };

            audio = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Play the video's audio.";
            };

            volume = lib.mkOption {
              type = lib.types.int;
              default = 15;
              description = "Audio volume (0–100). Only applies when audio is enabled.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.mapAttrsToList (
      monitor: _:
      "my.hypr.wallpapers: ${monitor} has no videos to play; add some to wallpapers/ on build-nix and run wallpapers-sync."
    ) (lib.removeAttrs cfg.monitors (lib.attrNames activeMonitors));

    systemd.user.services = lib.mapAttrs' (
      monitor: monCfg: lib.nameValuePair "wallpaper-${monitor}" (mkWallpaperService monitor monCfg)
    ) activeMonitors;

    # Restart a monitor's wallpaper after its mode changes or it reconnects, so
    # it gets a fresh surface and any video marked failed meanwhile is retried.
    wayland.windowManager.hyprland.extraConfig = lib.mkIf (activeMonitors != { }) ''
      dofile("${./wallpaper-monitor.lua}")({
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            monitor: _:
            "[${builtins.toJSON monitor}] = ${builtins.toJSON "${pkgs.systemd}/bin/systemctl --user --no-block try-restart ${lib.escapeShellArg "wallpaper-${monitor}.service"}"},"
          ) activeMonitors
        )}
      })
    '';
  };
}
