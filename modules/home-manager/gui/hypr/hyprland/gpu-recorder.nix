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

in
{
  options.my.hypr.gpuRecorder = {
    enable = lib.mkEnableOption "GPU Screen Recorder replay buffer";

    captureTarget = lib.mkOption {
      type = lib.types.str;
      default = "portal";
      description = "Capture target passed to -w: portal, focused, a monitor name (e.g. DP-1), region, etc.";
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
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.gpu-screen-recorder}"
          "-w ${lib.escapeShellArg cfg.captureTarget}"
          portalArgs
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
  };
}
