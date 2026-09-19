{
  self,
  lib,
  networkTopology,
  ...
}:
let
  # Leave false until the container exists and its forwarded port secret is set;
  # see docs/qbittorrent-migration.md.
  vpnClientEnabled = false;
  # Secret-backed features stay off until the SOPS values exist.
  secretsProvisioned = false;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/qbittorrent.nix"
    "${self}/modules/software/services/qbit-manage.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };

  networking.hostName = "qbit-lts-nix";

  my.secrets.qbit-lts-vpn.enable = vpnClientEnabled;
  my.secrets.qbittorrent_webui.enable = secretsProvisioned;
  my.secrets.qbit-trackers.enable = secretsProvisioned;

  # Seeding instance: torrents arrive already complete, at a path chosen when
  # they were downloaded. Nothing here may ever relocate or remove data.
  my.services.qbittorrent = {
    enable = true;
    profile = "lts";
    portSecret = lib.mkIf vpnClientEnabled "qbit_lts_vpn_port";
    webuiPasswordSecret = lib.mkIf secretsProvisioned "qbittorrent_webui_password";

    authSubnetWhitelist = [
      "${networkTopology.lib.lanIp "arrs-nix"}/32"
      "${networkTopology.lib.lanIp "qui-nix"}/32"
    ];
    serverDomains = [
      (networkTopology.lib.fqdn "qbit-lts-nix")
      (networkTopology.lib.lanIp "qbit-lts-nix")
      "localhost"
    ];

    # Only a fallback. Promoted torrents always arrive with an explicit path.
    defaultSavePath = "/mnt/downloadSSD/Seeding";
    tempPath = null;
    autoTMM = false;

    readWritePaths = [
      "/mnt/downloadHDD"
      "/mnt/downloadSSD"
    ];

    # Cosmetic here: labels are preserved on promotion, but with AutoTMM off no
    # path is ever enforced from them.
    categories = {
      sonarr.savePath = "/mnt/downloadHDD/downloads/sonarr";
      radarr.savePath = "/mnt/downloadHDD/downloads/radarr";
      lidarr.savePath = "/mnt/downloadSSD/Seeding";
      music-seed.savePath = "/mnt/downloadSSD/Seeding";
    };
  };

  # Seeding reads must never contend with Jellyfin.
  systemd.services.qbittorrent.serviceConfig.IOSchedulingClass = "idle";

  my.services.qbit-manage = {
    enable = secretsProvisioned;
    rootDir = "/mnt/downloadSSD/Seeding";
    # Stays on until a --dry-run has been read and found boring.
    dryRun = true;

    trackerSecrets = {
      t1 = "qbit_tracker_t1";
      t2 = "qbit_tracker_t2";
    };

    categories = {
      music-seed = "/mnt/downloadSSD/Seeding";
    };

    # Lowest priority wins; each torrent takes the first group it matches.
    # cleanup stays false everywhere: these .torrent files are the only copy of
    # their passkeys.
    shareLimits = {
      tier1 = {
        priority = 1;
        include_any_tags = [ "t1" ];
        min_seeding_time = "30d";
        max_ratio = -1;
        cleanup = false;
      };
      tier2 = {
        priority = 2;
        include_any_tags = [ "t2" ];
        min_seeding_time = "14d";
        max_ratio = -1;
        cleanup = false;
      };
      default = {
        priority = 99;
        max_ratio = -1;
        max_seeding_time = -1;
        cleanup = false;
      };
    };
  };

  my.network.vpnEgress.client = {
    enable = vpnClientEnabled;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-eu1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
