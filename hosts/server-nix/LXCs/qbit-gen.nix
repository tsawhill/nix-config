{
  self,
  lib,
  networkTopology,
  ...
}:
let
  # Routed through the Swiss gateway; forwarded port comes from SOPS.
  vpnClientEnabled = true;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/qbittorrent.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };

  networking.hostName = "qbit-gen-nix";

  my.secrets.qbit-gen-vpn.enable = vpnClientEnabled;
  my.secrets.qbittorrent_webui.enable = true;

  # Intake instance: every grab lands here, and anything that fails to import
  # stays here rather than reaching the seeding box.
  my.services.qbittorrent = {
    enable = true;
    profile = "gen";
    portSecret = lib.mkIf vpnClientEnabled "qbit_gen_vpn_port";
    webuiUsername = "taylor";
    webuiPasswordSecret = "qbittorrent_webui_password_gen";

    authSubnetWhitelist = [
      "${networkTopology.lib.lanIp "arrs-nix"}/32"
      "${networkTopology.lib.lanIp "qui-nix"}/32"
      "${networkTopology.lib.lanIp "taylor-desktop-nix"}/32"
      "${networkTopology.lib.lanIp "taylor-cube-nix"}/32"
      (networkTopology.lib.wgAddress "taylor-desktop-nix")
      (networkTopology.lib.wgAddress "taylor-cube-nix")
    ];
    serverDomains = [
      (networkTopology.lib.fqdn "qbit-gen-nix")
    ];

    defaultSavePath = "/mnt/downloadHDD/downloads/complete";
    tempPath = "/mnt/downloadHDD/downloads/incomplete";
    # Categories pick the pool here, so AutoTMM must be free to place new grabs.
    autoTMM = true;
    # Leaves tunnel headroom for the seed box and keeps a saturated link from
    # tripping the gateway's packet-loss rotation threshold.
    uploadLimit = 15000;

    readWritePaths = [
      "/mnt/downloadHDD"
      "/mnt/downloadSSD"
    ];

    categories = {
      tv-sonarr.savePath = "/mnt/downloadHDD/downloads/sonarr";
      radarr.savePath = "/mnt/downloadHDD/downloads/radarr";
      # TODO: confirm where Lidarr actually drops new grabs on downloadSSD.
      lidarr.savePath = "/mnt/downloadSSD/Seeding";
      prowlarr.savePath = "/mnt/downloadHDD/downloads/complete";
      manual.savePath = "/mnt/downloadHDD/downloads/complete";
    };
  };

  my.network.vpnEgress.client = {
    enable = vpnClientEnabled;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
