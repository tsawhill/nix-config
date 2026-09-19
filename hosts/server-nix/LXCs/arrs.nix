{ self, networkTopology, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/prowlarr.nix"
    "${self}/modules/software/services/radarr.nix"
    "${self}/modules/software/services/sonarr.nix"
    "${self}/modules/software/services/lidarr.nix"
    "${self}/modules/software/services/yt-dlp.nix"
    "${self}/modules/software/services/qbit-promote.nix"

  ];
  my.secrets = {
    radarr_api_key.enable = true;
    sonarr_api_key.enable = true;
    lidarr_api_key.enable = true;
    prowlarr_api_key.enable = true;
  };
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

  # Called by each *arr on successful import; see docs/qbittorrent-migration.md.
  my.services.qbit-promote = {
    enable = true;
    intakeUrl = "http://${networkTopology.lib.fqdn "qbit-gen-nix"}:8080";
    seedingUrl = "http://${networkTopology.lib.fqdn "qbit-lts-nix"}:8080";
  };

  networking.hostName = "arrs-nix";
}
