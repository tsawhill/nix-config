{ self, networkTopology, ... }:
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/prowlarr.nix"
    "${self}/modules/software/services/radarr.nix"
    "${self}/modules/software/services/sonarr.nix"
    "${self}/modules/software/services/lidarr.nix"
    "${self}/modules/software/services/yt-dlp.nix"
    "${self}/modules/software/services/qbit-promote.nix"
    "${self}/modules/software/services/flaresolverr.nix"

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

  # Reached by Prowlarr over loopback as http://127.0.0.1:8191.
  my.services.flaresolverr.enable = true;

  # Indexer queries leave through the Swiss gateway rather than OPNsense's own
  # tunnel, so the *arrs and the torrent clients share one exit.
  my.network.vpnEgress.client = {
    enable = true;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };

  networking.hostName = "arrs-nix";
}
