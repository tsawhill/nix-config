{ pkgs, lib, config, ... }:
{
  options.software.apps.media.enable = lib.mkEnableOption "media playback and editing apps";

  config = lib.mkIf config.software.apps.media.enable {
    # OBS with capture plugins
    programs.obs-studio = {
      enable = true;
      enableVirtualCamera = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture
        wlrobs
        obs-vkcapture
      ];
    };

    environment.systemPackages = with pkgs; [
      # Playback
      mpv
      feishin
      delfin

      # Editing
      audacity
      kdePackages.kdenlive
      gimp
    ];
  };
}
