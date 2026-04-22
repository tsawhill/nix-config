{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.my.hypr.wallpaperEngine;

  # Build the per-monitor rotation service
  mkWallpaperService =
    monitor: monCfg:
    let
      wallpaperList = lib.concatStringsSep " " (map lib.escapeShellArg monCfg.wallpapers);

      assetsArg = "--assets-dir ${lib.escapeShellArg cfg.assetsPath}";

      disableAppsCheck = lib.concatStringsSep " || " (
        map (app: "${pkgs.procps}/bin/pgrep -f ${lib.escapeShellArg app} > /dev/null 2>&1") cfg.disableApps
      );

      audioArgs =
        if !monCfg.audio then
          "--silent --no-audio-processing"
        else
          lib.concatStringsSep " " (
            lib.optional monCfg.silent "--silent"
            ++ lib.optional (!monCfg.silent) "--volume ${toString monCfg.volume}"
            ++ lib.optional (!monCfg.audioProcessing) "--no-audio-processing"
          );

      # Fake mpv config with null audio output — prevents PipeWire node creation
      mpvNullAudioConf = pkgs.writeTextDir "mpv.conf" "ao=null";

      audioEnv = lib.optionals (!monCfg.audio) [
        "SDL_AUDIODRIVER=dummy"
        "MPV_HOME=${mpvNullAudioConf}"
        "PULSE_SERVER=/dev/null"
      ];

      rotationScript = pkgs.writeShellScript "wallpaper-engine-${monitor}" ''
        WALLPAPERS=(${wallpaperList})
        COUNT=''${#WALLPAPERS[@]}

        trap 'kill $WPE_PID $SLEEP_PID 2>/dev/null; exit' SIGTERM SIGINT

        while true; do
          # Pause while any disable-app is running
          while ${disableAppsCheck}; do
            sleep 1
          done

          IDX=$(( RANDOM % COUNT ))
          WID=''${WALLPAPERS[$IDX]}

          ${lib.getExe pkgs.linux-wallpaperengine} \
            --screen-root ${lib.escapeShellArg monitor} \
            --bg "$WID" \
            --fps ${toString monCfg.fps} \
            --scaling ${monCfg.scaling} \
            --clamp ${cfg.clamping} \
            ${audioArgs} \
            ${assetsArg} &

          WPE_PID=$!

          # Run rotation sleep in background so we can interrupt it
          sleep ${lib.escapeShellArg monCfg.rotateInterval} &
          SLEEP_PID=$!

          # Wait until the interval ends or a disable-app starts
          while kill -0 $SLEEP_PID 2>/dev/null; do
            if ${disableAppsCheck}; then
              kill $SLEEP_PID 2>/dev/null
              kill $WPE_PID 2>/dev/null
              wait $WPE_PID 2>/dev/null
              WPE_PID=
              break
            fi
            sleep 5
          done

          if [ -n "$WPE_PID" ]; then
            kill $WPE_PID 2>/dev/null
            wait $WPE_PID 2>/dev/null
          fi
        done
      '';
    in
    {
      Unit = {
        Description = "Wallpaper Engine rotation for ${monitor}";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${rotationScript}";
        Environment = audioEnv;
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };

in
{
  options.my.hypr.wallpaperEngine = {
    enable = lib.mkEnableOption "linux-wallpaperengine with per-monitor rotation";

    assetsPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${config.home.homeDirectory}/.steam/steam/steamapps/common/wallpaper_engine/assets";
      description = "Path to the wallpaper_engine/assets directory.";
    };

    clamping = lib.mkOption {
      type = lib.types.enum [
        "clamp"
        "border"
        "repeat"
      ];
      default = "clamp";
      description = "Edge clamping mode applied to all monitors.";
    };

    disableApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "gamescope" ];
      description = "Patterns (matched via pgrep -f against the full command line) that pause all wallpaper rendering while any match is running.";
      example = [
        "gamescope"
        "wine"
      ];
    };

    monitors = lib.mkOption {
      default = { };
      description = "Per-monitor wallpaper configuration, keyed by monitor name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            wallpapers = lib.mkOption {
              type = lib.types.nonEmptyListOf lib.types.str;
              description = "Steam Workshop IDs to rotate through. A single ID disables rotation.";
              example = [
                "3272204393"
                "1234567890"
              ];
            };

            rotateInterval = lib.mkOption {
              type = lib.types.str;
              default = "1h";
              description = "How long each wallpaper is shown before switching. Accepts sleep(1) units: 30m, 1h, 6h, etc.";
            };

            fps = lib.mkOption {
              type = lib.types.int;
              default = 30;
            };

            scaling = lib.mkOption {
              type = lib.types.enum [
                "stretch"
                "fit"
                "fill"
                "default"
              ];
              default = "fill";
            };

            audio = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable wallpaper audio. When false, SDL audio is fully disabled (no PipeWire entries).";
            };

            silent = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Mute wallpaper audio. Only applies when audio is enabled.";
            };

            volume = lib.mkOption {
              type = lib.types.int;
              default = 15;
              description = "Audio volume (0–100). Only applies when audio is enabled and not silent.";
            };

            audioProcessing = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable audio processing/visualisation. Only applies when audio is enabled.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services = lib.mapAttrs' (
      monitor: monCfg: lib.nameValuePair "wallpaper-engine-${monitor}" (mkWallpaperService monitor monCfg)
    ) cfg.monitors;

    # wayland.windowManager.hyprland.settings.layerrule = [
    #   "idleinhibit never, linux-wallpaperengine"
    # ];
  };
}
