{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.my.hypr.gpuRecorder;

  audioArgs = lib.concatMapStringsSep " " (d: "-a ${lib.escapeShellArg d}") (
    cfg.audio.output ++ cfg.audio.input
  );

  # -restore-portal-session only applies when using the portal capture target
  portalArgs = lib.optionalString (cfg.captureTarget == "portal") "-restore-portal-session yes";

  recordingSavedNotification = pkgs.writeShellApplication {
    name = "gpu-recorder-notify-saved";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      file="''${1:-}"
      type="''${2:-}"

      # Replay saves already have their own keybind notification.
      if [[ "$type" != "regular" ]]; then
        exit 0
      fi

      if [[ -n "$file" ]]; then
        notify-send -t 3000 -u low -- "GPU Screen Recorder" "Recording saved: $(basename "$file")"
      else
        notify-send -t 3000 -u low -- "GPU Screen Recorder" "Recording saved"
      fi
    '';
  };

  recordingRunner = pkgs.writeShellApplication {
    name = "gpu-recorder-recording";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      output_dir=${lib.escapeShellArg cfg.outputDir}
      timestamp="$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)"
      output_file="$output_dir/$timestamp.mkv"

      mkdir -p "$output_dir"

      exec ${lib.getExe pkgs.gpu-screen-recorder} ${
        lib.concatStringsSep " " [
          "-w ${lib.escapeShellArg cfg.captureTarget}"
          # portalArgs
          "-f ${toString cfg.fps}"
          "-fm cfr -k hevc -bm qp -q very_high"
          audioArgs
          "-c mkv"
          "-sc ${lib.getExe recordingSavedNotification}"
          ''-o "$output_file"''
        ]
      }
    '';
  };

  recordingToggle = pkgs.writeShellApplication {
    name = "gpu-recorder-toggle-recording";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.systemd
    ];
    text = ''
      replay_service="gpu-recorder.service"
      recording_service="gpu-recorder-recording.service"

      notify() {
        notify-send -t 2000 -u low -- "GPU Screen Recorder" "$1"
      }

      if systemctl --user --quiet is-active "$recording_service"; then
        notify "Saving recording..."
        systemctl --user stop "$recording_service"
        systemctl --user start "$replay_service"
      else
        systemctl --user stop "$replay_service"
        systemctl --user start "$recording_service"

        if ! systemctl --user --quiet is-active "$recording_service"; then
          notify "Recording failed to start"
          systemctl --user start "$replay_service"
          exit 1
        fi

        notify "Recording started"
      fi
    '';
  };

in
{
  options.my.hypr.gpuRecorder = {
    enable = lib.mkEnableOption "GPU Screen Recorder replay buffer";

    captureTarget = lib.mkOption {
      type = lib.types.str;
      default = "portal";
      description = "Capture target passed to -w: screen, portal, focused, a monitor name (e.g. DP-1), region, etc.";
    };

    fps = lib.mkOption {
      type = lib.types.int;
      default = 60;
    };

    replayDuration = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Replay buffer duration in seconds.";
    };

    recordingToggleKeybind = lib.mkOption {
      type = lib.types.str;
      default = "$mainMod SHIFT, Next";
      description = "Hyprland keybind used to start/stop a regular GPU Screen Recorder recording.";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Videos/Raw";
    };

    audio = {
      output = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "default_output" ];
        description = "PipeWire audio output devices (run gpu-screen-recorder --list-audio-devices to see options).";
      };
      input = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "default_input" ];
        description = "PipeWire audio input devices (run gpu-screen-recorder --list-audio-devices to see options).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.gpu-recorder = {
      Unit = {
        Description = "GPU Screen Recorder (Replay Buffer)";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.outputDir}";
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.gpu-screen-recorder}"
          "-w ${lib.escapeShellArg cfg.captureTarget}"
          # portalArgs
          "-f ${toString cfg.fps}"
          "-fm cfr -k hevc -bm qp -q very_high"
          audioArgs
          "-r ${toString cfg.replayDuration}"
          "-c mkv"
          "-o ${lib.escapeShellArg cfg.outputDir}"
        ];
        Restart = "on-failure";
        RestartSec = "3s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };

    systemd.user.services.gpu-recorder-recording = {
      Unit = {
        Description = "GPU Screen Recorder (Manual Recording)";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
        Conflicts = [ "gpu-recorder.service" ];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.getExe recordingRunner;
        KillSignal = "SIGINT";
        TimeoutStopSec = "30s";
      };
    };

    wayland.windowManager.hyprland.settings.bindl = [
      "${cfg.recordingToggleKeybind}, exec, ${lib.getExe recordingToggle}"
    ];
  };
}
