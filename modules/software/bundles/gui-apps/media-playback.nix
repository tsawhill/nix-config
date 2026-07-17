{
  pkgs,
  lib,
  config,
  self,
  ...
}:
{
  options.software.apps.media-playback.enable = lib.mkEnableOption "media playback apps";

  config = lib.mkIf config.software.apps.media-playback.enable {
    nix.settings = {
      extra-substituters = [ "https://kopuz.cachix.org" ];
      extra-trusted-public-keys = [ "kopuz.cachix.org-1:J2X3AnAYhKTJW5S3aCLoA1ckonQXVNZMQvhZA0YAufw=" ];
    };

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
      # self.packages.${pkgs.stdenv.hostPlatform.system}.kopuz
    ];
  };
}
