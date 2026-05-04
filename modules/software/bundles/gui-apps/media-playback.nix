{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.apps.media-playback.enable = lib.mkEnableOption "media playback apps";

  config = lib.mkIf config.software.apps.media-playback.enable {
    # OBS with capture plugins
    programs.obs-studio = {
      enable = true;
      enableVirtualCamera = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture
        wlrobs
      ];
    };

    environment.systemPackages = with pkgs; [
      mpv
      feishin
      delfin
    ];
  };
}
