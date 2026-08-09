{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.my.hypr.gpuRecorder;
  hyprCfg = config.my.hypr;
  primaryMonitorFile = "${config.home.homeDirectory}/.local/state/hypr-primary-monitor";
  activationEnabled = cfg.activation.processPatterns != [ ];

  activationCheck =
    if activationEnabled then
      lib.concatStringsSep " || " (
        map (
          pattern:
          "${pkgs.procps}/bin/pgrep --ignore-case --full -- ${lib.escapeShellArg pattern} > /dev/null 2>&1"
        ) cfg.activation.processPatterns
      )
    else
      "false";

  # Translate a hyprlang bind prefix ("$mainMod SHIFT, Key") into a Lua key
  # expression for hl.bind, referencing the `mainMod` local from default.nix.
  keyExpr =
    spec:
    let
      toks = lib.filter (t: t != "") (lib.splitString " " (lib.replaceStrings [ "," ] [ " " ] spec));
      key = lib.last toks;
      mods = lib.init toks;
      otherMods = lib.filter (t: t != "$mainMod") mods;
      suffix = lib.concatStringsSep " + " (otherMods ++ [ key ]);
    in
    if lib.elem "$mainMod" mods then ''mainMod .. " + ${suffix}"'' else ''"${suffix}"'';

  audioArgs = lib.concatMapStringsSep " " (d: "-a ${lib.escapeShellArg d}") (
    cfg.audio.output ++ cfg.audio.input
  );

  captureTargetResolver = pkgs.writeShellApplication {
    name = "gpu-recorder-capture-target";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      configured_target=${lib.escapeShellArg cfg.captureTarget}
      state_file=${lib.escapeShellArg primaryMonitorFile}
      fallback_primary=${lib.escapeShellArg hyprCfg.monitors.primary}

      if [[ "$configured_target" != "primary" ]]; then
        printf '%s\n' "$configured_target"
        exit 0
      fi

      if [[ -s "$state_file" ]]; then
        IFS= read -r primary_monitor < "$state_file" || true
        if [[ -n "$primary_monitor" ]]; then
          printf '%s\n' "$primary_monitor"
          exit 0
        fi
      fi

      if [[ -n "$fallback_primary" ]]; then
        printf '%s\n' "$fallback_primary"
      else
        printf '%s\n' "portal"
      fi
    '';
  };

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
      mode="''${1:-recording}"
      output_dir=${lib.escapeShellArg cfg.outputDir}
      capture_target="$(${lib.getExe captureTargetResolver})"
      timestamp="$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)"
      output_file="$output_dir/$timestamp.mkv"

      mkdir -p "$output_dir"

      if [[ "$mode" == "--replay" ]]; then
        exec ${lib.getExe pkgs.gpu-screen-recorder} ${
          lib.concatStringsSep " " ([
            ''-w "$capture_target"''
            "-f ${toString cfg.fps}"
            "-fm cfr -k ${lib.escapeShellArg cfg.videoCodec} -bm qp -q ${cfg.quality}"
            audioArgs
            "-r ${toString cfg.replayDuration}"
            "-c mkv"
            ''-o "$output_dir"''
          ] ++ cfg.extraArgs)
        }
      fi

      exec ${lib.getExe pkgs.gpu-screen-recorder} ${
        lib.concatStringsSep " " ([
          ''-w "$capture_target"''
          "-f ${toString cfg.fps}"
          "-fm cfr -k ${lib.escapeShellArg cfg.videoCodec} -bm qp -q ${cfg.quality}"
          audioArgs
          "-c mkv"
          "-sc ${lib.getExe recordingSavedNotification}"
          ''-o "$output_file"''
        ] ++ cfg.extraArgs)
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

  sourcePicker = pkgs.writeShellApplication {
    name = "gpu-recorder-pick-source";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.systemd
    ];
    text = ''
      replay_service="gpu-recorder.service"
      recording_service="gpu-recorder-recording.service"
      token_file="''${XDG_CONFIG_HOME:-$HOME/.config}/gpu-screen-recorder/restore_token"

      notify() {
        notify-send -t 2000 -u low -- "GPU Screen Recorder" "$1"
      }

      if systemctl --user --quiet is-active "$recording_service"; then
        notify "Stop recording before changing source"
        exit 1
      fi

      systemctl --user stop "$replay_service"
      rm -f "$token_file"
      notify "Pick replay source"
      systemctl --user start "$replay_service"
    '';
  };

  replayActivationWatcher = pkgs.writeShellApplication {
    name = "gpu-recorder-activation-watcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      replay_service="gpu-recorder.service"
      recording_service="gpu-recorder-recording.service"
      stop_delay=${toString cfg.activation.stopDelaySeconds}
      poll_interval=${toString cfg.activation.pollIntervalSeconds}
      stop_deadline=0

      cleanup() {
        systemctl --user stop "$replay_service" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      while true; do
        if ${activationCheck}; then
          stop_deadline=0
          if ! systemctl --user --quiet is-active "$replay_service" \
            && ! systemctl --user --quiet is-active "$recording_service"; then
            systemctl --user start "$replay_service"
          fi
        elif systemctl --user --quiet is-active "$recording_service"; then
          # Never interrupt a recording started manually.
          stop_deadline=0
        elif systemctl --user --quiet is-active "$replay_service"; then
          now=$(date +%s)
          if (( stop_deadline == 0 )); then
            stop_deadline=$((now + stop_delay))
          elif (( now >= stop_deadline )); then
            systemctl --user stop "$replay_service"
            stop_deadline=0
          fi
        else
          stop_deadline=0
        fi

        sleep "$poll_interval"
      done
    '';
  };

in
{
  options.my.hypr.gpuRecorder = {
    enable = lib.mkEnableOption "GPU Screen Recorder replay buffer";

    captureTarget = lib.mkOption {
      type = lib.types.str;
      default = "portal";
      description = "Capture target passed to -w: primary, screen, portal, focused, a monitor name (e.g. DP-1), region, etc.";
    };

    fps = lib.mkOption {
      type = lib.types.int;
      default = 60;
    };

    videoCodec = lib.mkOption {
      type = lib.types.str;
      default = "hevc";
      description = "Video codec passed to -k, for example hevc, hevc_hdr, av1, or av1_hdr.";
    };

    quality = lib.mkOption {
      type = lib.types.enum [
        "medium"
        "high"
        "very_high"
        "ultra"
      ];
      default = "very_high";
      description = "Video quality preset passed to -q.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments passed to gpu-screen-recorder (e.g. -tune quality, -ffmpeg-opts).";
    };

    replayDuration = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Replay buffer duration in seconds.";
    };

    activation = {
      processPatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "gamescope"
          "runelite"
        ];
        description = "Case-insensitive patterns matched against full process command lines. An empty list starts the replay buffer with the session.";
      };

      stopDelaySeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 60;
        description = "Seconds to keep the replay buffer running after the last matching process exits.";
      };

      pollIntervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Seconds between activation process checks.";
      };
    };

    recordingToggleKeybind = lib.mkOption {
      type = lib.types.str;
      default = "$mainMod SHIFT, Next";
      description = "Hyprland keybind used to start/stop a regular GPU Screen Recorder recording.";
    };

    sourcePickerKeybind = lib.mkOption {
      type = lib.types.str;
      default = "$mainMod CTRL, Next";
      description = "Hyprland keybind used to restart the replay buffer and pick a portal source.";
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
    home.file.".local/share/luts/pq-to-sdr.cube".source = ./assets/pq-to-sdr.cube;

    systemd.user.services.gpu-recorder = {
      Unit = {
        Description = "GPU Screen Recorder (Replay Buffer)";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.outputDir}";
        ExecStart = "${lib.getExe recordingRunner} --replay";
        Restart = "on-failure";
        RestartSec = "3s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "30s";
      };
      Install.WantedBy = lib.optionals (!activationEnabled) [ "wayland-session@hyprland.desktop.target" ];
    };

    systemd.user.services.gpu-recorder-activation = lib.mkIf activationEnabled {
      Unit = {
        Description = "GPU Screen Recorder process activation watcher";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.getExe replayActivationWatcher;
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

    # Locked binds (hl.bind ... { locked = true }) so they fire in-game.
    wayland.windowManager.hyprland.extraConfig =
      ''
        hl.bind(${keyExpr cfg.recordingToggleKeybind}, hl.dsp.exec_cmd("${lib.getExe recordingToggle}"), { locked = true })
      ''
      + lib.optionalString (cfg.captureTarget == "portal") ''
        hl.bind(${keyExpr cfg.sourcePickerKeybind}, hl.dsp.exec_cmd("${lib.getExe sourcePicker}"), { locked = true })
      '';
  };
}
