{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.my.hypr.gpuRecorder;
  monCfg = config.my.hypr.monitors;

  audioArgs = lib.concatMapStringsSep " " (d: "-a ${lib.escapeShellArg d}") (
    cfg.audio.output ++ cfg.audio.input
  );

  # Wrapper that reads swap state to determine which monitor is currently primary
  launchScript = pkgs.writeShellScript "gpu-screen-recorder-launch" ''
    STATE_FILE="$HOME/.local/state/hypr-swap-state"
    if [ -f "$STATE_FILE" ]; then
      MONITOR=${lib.escapeShellArg monCfg.secondary}
    else
      MONITOR=${lib.escapeShellArg monCfg.primary}
    fi
    exec ${lib.getExe pkgs.gpu-screen-recorder} \
      -w "$MONITOR" \
      -f ${toString cfg.fps} \
      -fm cfr -k hevc -bm qp -q very_high \
      ${audioArgs} \
      -r ${toString cfg.replayDuration} \
      -c mkv \
      -o ${lib.escapeShellArg cfg.outputDir}
  '';

in
{
  options.my.hypr.gpuRecorder = {
    enable = lib.mkEnableOption "GPU Screen Recorder replay buffer";

    fps = lib.mkOption {
      type = lib.types.int;
      default = 60;
    };

    replayDuration = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Replay buffer duration in seconds.";
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
    systemd.user.services.gpu-screen-recorder = {
      Unit = {
        Description = "GPU Screen Recorder (Replay Buffer)";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.outputDir}";
        ExecStart = "${launchScript}";
        Restart = "on-failure";
        RestartSec = "3s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };
  };
}
