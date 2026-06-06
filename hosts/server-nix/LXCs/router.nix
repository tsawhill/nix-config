{
  config,
  lib,
  networkTopology,
  self,
  ...
}:

let
  secrets = config.sops.secrets;
  topologyHosts = networkTopology.hosts;
  inherit (networkTopology.lib) lanIp wgIp;

  trustedWgRemoteClients = [
    (wgIp "taylor-desktop-nix")
    (wgIp "taylor-laptop-nix")
    (wgIp "taylor-deck-nix")
    (wgIp "pixel7pro")
    (wgIp "fwlaptop")
  ];

  reservationHosts = lib.filterAttrs (
    _: host: host ? lan && host.lan ? ip && host.lan ? mac
  ) topologyHosts;

  reservations = lib.mapAttrsToList (name: host: {
    inherit (host.lan) mac;
    ip = host.lan.ip;
    hostname = host.lan.dhcpHostname or name;
    description = name;
  }) reservationHosts;
in
{
  imports = [
    ./base
    self.nixosModules.router
  ];

  networking.hostName = "router-nix";
  my.secrets.wireguard.router-nix.enable = true;
  my.secrets.wireguard.pubkeys.enable = true;

  # The base LXC profile configures eth0 with DHCP. The router container owns
  # its interfaces explicitly so LAN/WAN naming stays stable and auditable.
  systemd.network.networks."50-eth0".enable = lib.mkForce false;

  my.router = {
    enable = true;

    interfaces = {
      lan = {
        name = "lan0";
        role = "lan";
        address = networkTopology.networks.lan.gateway;
        prefixLength = 24;
        requiredForOnline = "routable";
        dhcp = {
          enable = true;
          subnet = networkTopology.networks.lan.cidr;
          rangeStart = networkTopology.networks.lan.dhcpPool.start;
          rangeEnd = networkTopology.networks.lan.dhcpPool.end;
          gateway = networkTopology.networks.lan.gateway;
          dnsServers = [ (lanIp networkTopology.networks.lan.dnsHost) ];
          domain = networkTopology.domains.dhcp;
          inherit reservations;
        };
      };

      wan = {
        name = "wan0";
        role = "wan";
        dhcpClient = true;
        requiredForOnline = "no";
      };
    };

    wireguard = {
      servers.wg-remote = {
        address = "${networkTopology.networks.wgRemote.routerAddress}/24";
        listenPort = networkTopology.networks.wgRemote.port;
        privateKeyFile = secrets.router_wg_remote_private_key.path;
        peers = [
          {
            name = "Oracle-Rocky-Proxy";
            publicKeyFile = secrets.wg_pubkey_oracle_rocky_proxy.path;
            allowedIPs = [ "${wgIp "oracle-rocky-proxy"}/32" ];
            persistentKeepalive = 25;
          }
          {
            name = "Pixel7Pro";
            publicKeyFile = secrets.wg_pubkey_pixel7pro.path;
            allowedIPs = [ "${wgIp "pixel7pro"}/32" ];
          }
          {
            name = "FWLaptop";
            publicKeyFile = secrets.wg_pubkey_fwlaptop.path;
            allowedIPs = [ "${wgIp "fwlaptop"}/32" ];
          }
          {
            name = "pi-backup-nix";
            publicKeyFile = secrets.wg_pubkey_pi_backup_nix.path;
            allowedIPs = [ "${wgIp "pi-backup-nix"}/32" ];
          }
          {
            name = "taylor-desktop-nix";
            publicKeyFile = secrets.wg_pubkey_taylor_desktop_nix.path;
            allowedIPs = [ "${wgIp "taylor-desktop-nix"}/32" ];
          }
          {
            name = "taylor-laptop-nix";
            publicKeyFile = secrets.wg_pubkey_taylor_laptop_nix.path;
            allowedIPs = [ "${wgIp "taylor-laptop-nix"}/32" ];
          }
          {
            name = "taylor-deck-nix";
            publicKeyFile = secrets.wg_pubkey_taylor_deck_nix.path;
            allowedIPs = [ "${wgIp "taylor-deck-nix"}/32" ];
          }
        ];
      };

      clients = {
        wg-airvpn-ch = {
          address = "10.134.43.233/32";
          privateKeyFile = secrets.router_wg_airvpn_ch_private_key.path;
          publicKeyFile = secrets.wg_pubkey_airvpn.path;
          presharedKeyFile = secrets.router_wg_airvpn_ch_preshared_key.path;
          endpoint = "62.102.148.218:1637";
          mtu = 1320;
          gateway = "10.134.43.232";
          fwMark = 257;
          routeTable = 101;
          routePriority = 10100;
        };

        wg-airvpn-na = {
          address = "10.172.0.216/32";
          privateKeyFile = secrets.router_wg_airvpn_na_private_key.path;
          publicKeyFile = secrets.wg_pubkey_airvpn.path;
          presharedKeyFile = secrets.router_wg_airvpn_na_preshared_key.path;
          endpoint = "198.44.134.6:1637";
          gateway = "10.172.0.215";
          fwMark = 259;
          routeTable = 103;
          routePriority = 10300;
        };
      };
    };

    firewall = {
      aliases = {
        local_addresses.values = [
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
        ];
        vpn_zurich.values = [
          (lanIp "deluge-nix")
          (lanIp "arrs-nix")
          (lanIp "socks5-vpn-eu-nix")
        ];
        vpn_sanjose.values = [
          (lanIp "unbound-vpn-na-nix")
          (lanIp "searx-nix")
        ];
        host_amcrest_cameras.values = [ (lanIp "amcrest-cameras") ];
        trusted_wg_remote_clients.values = trustedWgRemoteClients;
        host_pi_backup_wireguard.values = [ (wgIp "pi-backup-nix") ];
      };

      allowedWan.udp = [ networkTopology.networks.wgRemote.port ];
      masqueradeInterfaces = [
        "wg-airvpn-ch"
        "wg-airvpn-na"
      ];

      portForwards = [
        {
          name = "Deluge AirVPN Zurich port";
          inInterface = "wg-airvpn-ch";
          originalPort = 47096;
          destination = lanIp "deluge-nix";
          destinationPort = 47096;
        }
      ];

      # Firewall rules are written like an OPNsense interface page: choose the
      # ingress interface, then list block/pass rules in the order they should
      # appear. The module turns this into nftables forward-chain rules.
      rules = {
        lan0 = {
          block = [
            {
              from = "@host_amcrest_cameras";
              to = "!${networkTopology.networks.lan.cidr}";
              comment = "Block cameras from using internet";
            }
            {
              from = "@vpn_zurich";
              to = "!@local_addresses";
              outInterface = "wan0";
              comment = "Kill switch: Zurich VPN clients never exit WAN";
            }
            {
              from = "@vpn_sanjose";
              to = "!@local_addresses";
              outInterface = "wan0";
              comment = "Kill switch: San Jose VPN clients never exit WAN";
            }
          ];

          allow = [
            {
              to = networkTopology.networks.wgRemote.cidr;
              comment = "LAN to remote WireGuard network";
            }
          ];
        };

        "wg-remote" = {
          allow = [
            {
              from = "@trusted_wg_remote_clients";
              comment = "Trusted remote client full access";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "vaultwarden-nix";
              protocols = [ "tcp" ];
              ports = [ 8000 ];
              comment = "pi-backup to Vaultwarden";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "searx-nix";
              protocols = [ "tcp" ];
              ports = [ 8080 ];
              comment = "pi-backup to Searx";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "authentik-nix";
              protocols = [ "tcp" ];
              ports = [ 9000 ];
              comment = "pi-backup to Authentik";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "nextcloud-nix";
              protocols = [ "tcp" ];
              ports = [ 80 ];
              comment = "pi-backup to Nextcloud";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "arrs-nix";
              protocols = [ "tcp" ];
              ports = [
                6767
                7878
                8686
                8989
                9696
                5055
              ];
              comment = "pi-backup to Arrs";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "jellyfin-nix";
              protocols = [ "tcp" ];
              ports = [ 8096 ];
              comment = "pi-backup to Jellyfin";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "jellyseerr-nix";
              protocols = [ "tcp" ];
              ports = [ 5055 ];
              comment = "pi-backup to Jellyseerr";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "immich-nix";
              protocols = [ "tcp" ];
              ports = [ 2283 ];
              comment = "pi-backup to Immich";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "taylor-desktop-nix";
              protocols = [ "tcp" ];
              ports = [ 27017 ];
              comment = "pi-backup to BOIII";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "pufferpanel-nix";
              protocols = [ "tcp" ];
              ports = [ 25565 ];
              comment = "pi-backup to Pufferpanel";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = lanIp "gotify-nix";
              protocols = [ "tcp" ];
              ports = [ 80 ];
              comment = "pi-backup to Gotify";
            }
          ];
        };
      };

      # Policy routes are the readable form of nftables mangle mark rules. Each
      # entry names the WireGuard client tunnel instead of exposing the mark.
      policyRoutes = [
        {
          from = "@vpn_zurich";
          to = "!@local_addresses";
          via = "wg-airvpn-ch";
          comment = "EU VPN clients exit via Zurich";
        }
        {
          from = "@vpn_sanjose";
          to = "!@local_addresses";
          via = "wg-airvpn-na";
          comment = "US VPN clients exit via San Jose";
        }
      ];
    };
  };
}
