{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/prowlarr.nix"
    "${self}/modules/software/services/radarr.nix"
    "${self}/modules/software/services/sonarr.nix"
    "${self}/modules/software/services/lidarr.nix"
    "${self}/modules/software/services/yt-dlp.nix"

  ];
  my.groups = {
    media = {
      enable = true;
      members = [ "root" ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [ "root" ];
      gid = 1001;
    };
  };
  networking.hostName = "arrs-nix";
}
