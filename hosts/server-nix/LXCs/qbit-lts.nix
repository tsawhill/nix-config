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
  my.secrets.qbit-trackers.enable = secretsProvisioned;

  # Seeding instance: torrents arrive already complete, at a path chosen when
  # they were downloaded. Nothing here may ever relocate or remove data.
  my.services.qbittorrent = {
    enable = true;
    profile = "lts";
    portSecret = lib.mkIf vpnClientEnabled "qbit_lts_vpn_port";

    authSubnetWhitelist = [
      "${networkTopology.lib.lanIp "arrs-nix"}/32"
      "${networkTopology.lib.lanIp "qui-nix"}/32"
      "${networkTopology.lib.lanIp "taylor-desktop-nix"}/32"
      "${networkTopology.lib.lanIp "taylor-cube-nix"}/32"
      (networkTopology.lib.wgAddress "taylor-desktop-nix")
      (networkTopology.lib.wgAddress "taylor-cube-nix")
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
    # Hourly, not daily: unlisted trackers are meant to stop promptly, and the
    # timer is the real bound on how long they seed.
    interval = "hourly";
    # Stays on until a --dry-run has been read and found boring.
    dryRun = true;

    trackerSecrets = {
      t1 = "qbit_tracker_t1";
      t2 = "qbit_tracker_t2";
      t3 = "qbit_tracker_t3";
    };

    categories = {
      music-seed = "/mnt/downloadSSD/Seeding";
    };

    # Lowest priority wins; each torrent takes the first group it matches.
    # Promotion to this host is universal, so these only govern how long a
    # torrent seeds once it arrives.
    shareLimits = {
      # Seed forever.
      t1 = {
        priority = 1;
        include_any_tags = [ "t1" ];
        max_ratio = -1;
        max_seeding_time = -1;
        cleanup = false;
      };
      # 30 days, then remove the torrent and free the download copy.
      t2 = {
        priority = 2;
        include_any_tags = [ "t2" ];
        max_ratio = -1;
        max_seeding_time = "30d";
        cleanup = true;
      };
      # 2 days, then remove.
      t3 = {
        priority = 3;
        include_any_tags = [ "t3" ];
        max_ratio = -1;
        max_seeding_time = "2d";
        cleanup = true;
      };
      # Unlisted trackers stop and are cleaned up: everything promoted here came
      # through an *arr import, so the download copy is a seeding artifact and
      # the library already has the media. Removal goes via the recycle bin.
      default = {
        priority = 99;
        max_ratio = -1;
        max_seeding_time = 0;
        share_limit_action = "Stop";
        resume_torrent_after_change = false;
        cleanup = true;
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
