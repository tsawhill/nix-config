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

      rotationScript = pkgs.writeShellScript "wallpaper-engine-${monitor}" ''
        WALLPAPERS=(${wallpaperList})
        COUNT=''${#WALLPAPERS[@]}

        trap 'kill $WPE_PID 2>/dev/null; exit' SIGTERM SIGINT

        while true; do
          IDX=$(( RANDOM % COUNT ))
          WID=''${WALLPAPERS[$IDX]}

          ${lib.getExe pkgs.linux-wallpaperengine} \
            --screen-root ${lib.escapeShellArg monitor} \
            --bg "$WID" \
            --fps ${toString monCfg.fps} \
            --scaling ${monCfg.scaling} \
            --clamp ${cfg.clamping} \
            ${lib.optionalString monCfg.silent "--silent"} \
            ${lib.optionalString (!monCfg.audioProcessing) "--no-audio-processing"} \
            ${assetsArg} &

          WPE_PID=$!
          sleep ${lib.escapeShellArg monCfg.rotateInterval}
          kill $WPE_PID 2>/dev/null
          wait $WPE_PID 2>/dev/null
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

            silent = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Mute wallpaper audio.";
            };

            audioProcessing = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable audio processing/visualisation.";
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
