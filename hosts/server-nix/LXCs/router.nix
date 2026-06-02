{
  config,
  lib,
  self,
  ...
}:

let
  secrets = config.sops.secrets;

  hosts = {
    netgear-switch = "10.73.73.2";
    samba-nix = "10.73.73.4";
    unbound-vpn-na-nix = "10.73.73.5";
    adguard-nix = "10.73.73.6";
    llm-nix = "10.73.73.7";
    local-nginx-nix = "10.73.73.8";
    vaultwarden-nix = "10.73.73.9";
    acme-nix = "10.73.73.10";
    socks5-vpn-eu-nix = "10.73.73.11";
    immich-nix = "10.73.73.12";
    arrs-nix = "10.73.73.13";
    syncthing-nix = "10.73.73.14";
    jellyfin-nix = "10.73.73.15";
    searx-nix = "10.73.73.16";
    nextcloud-nix = "10.73.73.18";
    romm-nix = "10.73.73.19";
    deluge-nix = "10.73.73.20";
    amcrest-cameras = "10.73.73.21";
    jellyseerr-nix = "10.73.73.26";
    gotify-nix = "10.73.73.27";
    authentik-nix = "10.73.73.29";
    pufferpanel-nix = "10.73.73.30";
    build-nix = "10.73.73.40";
    unifi-nix = "10.73.73.41";
    pi-backup-lan = "10.73.73.42";
    laptop-nix = "10.73.73.68";
    desktop-nix = "10.73.73.69";
    printer = "10.73.73.71";
    deck-nix = "10.73.73.73";
    sunshine-nix = "10.73.73.140";
  };

  wgRemoteClients = {
    oracle-rocky-proxy = "10.50.50.16";
    pixel7pro = "10.50.50.11";
    fwlaptop = "10.50.50.15";
    pi-backup-nix = "10.50.50.5";
    taylor-desktop-nix = "10.50.50.2";
    taylor-laptop-nix = "10.50.50.3";
  };

  trustedWgRemoteClients = [
    wgRemoteClients.taylor-desktop-nix
    wgRemoteClients.taylor-laptop-nix
    wgRemoteClients.pixel7pro
    wgRemoteClients.fwlaptop
  ];

  reservations = [
    { mac = "28:80:88:70:5a:b0"; ip = hosts.netgear-switch; hostname = "netgear-switch"; description = "netgear-switch"; }
    { mac = "bc:24:11:0f:b8:97"; ip = hosts.samba-nix; hostname = "samba-nix"; description = "samba-nix"; }
    { mac = "a6:1e:69:87:fb:f3"; ip = hosts.unbound-vpn-na-nix; hostname = "unbound-vpn-na-nix"; description = "unbound-vpn-na-nix"; }
    { mac = "bc:24:11:cd:cd:ec"; ip = hosts.adguard-nix; hostname = "adguard-nix"; description = "adguard-nix"; }
    { mac = "bc:24:11:40:c1:43"; ip = hosts.llm-nix; hostname = "llm-nix"; description = "llm-nix"; }
    { mac = "bc:24:11:42:40:51"; ip = hosts.local-nginx-nix; hostname = "local-nginx-nix"; description = "local-nginx-nix"; }
    { mac = "bc:24:11:f5:ac:e2"; ip = hosts.vaultwarden-nix; hostname = "vaultwarden-nix"; description = "vaultwarden-nix"; }
    { mac = "bc:24:11:d5:6e:ab"; ip = hosts.acme-nix; hostname = "acme-nix"; description = "acme-nix"; }
    { mac = "bc:24:11:51:dd:4e"; ip = hosts.socks5-vpn-eu-nix; hostname = "socks5-vpn-eu-nix"; description = "socks5-vpn-eu-nix"; }
    { mac = "bc:24:11:de:09:b6"; ip = hosts.immich-nix; hostname = "immich-nix"; description = "immich-nix"; }
    { mac = "bc:24:11:59:07:12"; ip = hosts.arrs-nix; hostname = "arrs-nix"; description = "arrs-nix"; }
    { mac = "10:66:6a:aa:e3:ba"; ip = hosts.syncthing-nix; hostname = "syncthing-nix"; description = "syncthing-nix"; }
    { mac = "bc:24:11:92:d7:50"; ip = hosts.jellyfin-nix; hostname = "jellyfin-nix"; description = "jellyfin-nix"; }
    { mac = "02:ff:b9:66:68:1e"; ip = hosts.searx-nix; hostname = "searx-nix"; description = "searx-nix"; }
    { mac = "bc:24:11:60:3d:cc"; ip = hosts.nextcloud-nix; hostname = "nextcloud-nix"; description = "nextcloud-nix"; }
    { mac = "10:66:6a:5a:5b:80"; ip = hosts.romm-nix; hostname = "romm-nix"; description = "romm-nix"; }
    { mac = "bc:24:11:43:7d:c4"; ip = hosts.deluge-nix; hostname = "deluge-nix"; description = "deluge-nix"; }
    { mac = "bc:24:11:23:f8:93"; ip = hosts.jellyseerr-nix; hostname = "jellyseerr-nix"; description = "jellyseerr-nix"; }
    { mac = "bc:24:11:2b:3d:4a"; ip = hosts.gotify-nix; hostname = "gotify-nix"; description = "gotify-nix"; }
    { mac = "8e:95:4f:6e:c7:13"; ip = hosts.authentik-nix; hostname = "authentik-nix"; description = "authentik-nix"; }
    { mac = "bc:24:11:9d:2b:70"; ip = hosts.pufferpanel-nix; hostname = "pufferpanel-nix"; description = "pufferpanel-nix"; }
    { mac = "bc:24:11:e1:63:a2"; ip = hosts.build-nix; hostname = "build-nix"; description = "build-nix"; }
    { mac = "bc:24:11:50:c5:51"; ip = hosts.unifi-nix; hostname = "unifi-nix"; description = "unifi-nix"; }
    { mac = "88:a2:9e:77:6d:8b"; ip = hosts.pi-backup-lan; hostname = "pi-backup-nix"; description = "pi-backup-nix"; }
    { mac = "b0:dc:ef:20:5c:ba"; ip = hosts.laptop-nix; hostname = "laptop-nix"; description = "laptop-nix"; }
    { mac = "c8:7f:54:6c:e2:96"; ip = hosts.desktop-nix; hostname = "desktop-nix"; description = "desktop-nix"; }
    { mac = "38:7a:cc:42:d1:de"; ip = hosts.printer; hostname = "printer"; description = "printer"; }
    { mac = "b4:8c:9d:7e:6d:73"; ip = hosts.deck-nix; hostname = "deck-nix"; description = "deck-nix"; }
    { mac = "02:7d:da:73:cc:0d"; ip = hosts.sunshine-nix; hostname = "sunshine-nix"; description = "sunshine-nix"; }
  ];
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
        address = "10.73.73.1";
        prefixLength = 24;
        requiredForOnline = "routable";
        dhcp = {
          enable = true;
          subnet = "10.73.73.0/24";
          rangeStart = "10.73.73.100";
          rangeEnd = "10.73.73.245";
          gateway = "10.73.73.1";
          dnsServers = [ hosts.adguard-nix ];
          domain = "home.arpa";
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
        address = "10.50.50.1/24";
        listenPort = 51820;
        privateKeyFile = secrets.router_wg_remote_private_key.path;
        peers = [
          {
            name = "Oracle-Rocky-Proxy";
            publicKeyFile = secrets.wg_pubkey_oracle_rocky_proxy.path;
            allowedIPs = [ "${wgRemoteClients.oracle-rocky-proxy}/32" ];
            persistentKeepalive = 25;
          }
          {
            name = "Pixel7Pro";
            publicKeyFile = secrets.wg_pubkey_pixel7pro.path;
            allowedIPs = [ "${wgRemoteClients.pixel7pro}/32" ];
          }
          {
            name = "FWLaptop";
            publicKeyFile = secrets.wg_pubkey_fwlaptop.path;
            allowedIPs = [ "${wgRemoteClients.fwlaptop}/32" ];
          }
          {
            name = "pi-backup-nix";
            publicKeyFile = secrets.wg_pubkey_pi_backup_nix.path;
            allowedIPs = [ "${wgRemoteClients.pi-backup-nix}/32" ];
          }
          {
            name = "taylor-desktop-nix";
            publicKeyFile = secrets.wg_pubkey_taylor_desktop_nix.path;
            allowedIPs = [ "${wgRemoteClients.taylor-desktop-nix}/32" ];
          }
          {
            name = "taylor-laptop-nix";
            publicKeyFile = secrets.wg_pubkey_taylor_laptop_nix.path;
            allowedIPs = [ "${wgRemoteClients.taylor-laptop-nix}/32" ];
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
          hosts.deluge-nix
          hosts.arrs-nix
          hosts.socks5-vpn-eu-nix
        ];
        vpn_sanjose.values = [
          hosts.unbound-vpn-na-nix
          hosts.searx-nix
        ];
        host_amcrest_cameras.values = [ hosts.amcrest-cameras ];
        trusted_wg_remote_clients.values = trustedWgRemoteClients;
        host_pi_backup_wireguard.values = [ wgRemoteClients.pi-backup-nix ];
      };

      allowedWan.udp = [ 51820 ];
      masqueradeInterfaces = [
        "wg-airvpn-ch"
        "wg-airvpn-na"
      ];

      portForwards = [
        {
          name = "Deluge AirVPN Zurich port";
          inInterface = "wg-airvpn-ch";
          originalPort = 47096;
          destination = hosts.deluge-nix;
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
              to = "!10.73.73.0/24";
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
              to = "10.50.50.0/24";
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
              to = hosts.vaultwarden-nix;
              protocols = [ "tcp" ];
              ports = [ 8000 ];
              comment = "pi-backup to Vaultwarden";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.searx-nix;
              protocols = [ "tcp" ];
              ports = [ 8080 ];
              comment = "pi-backup to Searx";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.authentik-nix;
              protocols = [ "tcp" ];
              ports = [ 9000 ];
              comment = "pi-backup to Authentik";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.nextcloud-nix;
              protocols = [ "tcp" ];
              ports = [ 80 ];
              comment = "pi-backup to Nextcloud";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.arrs-nix;
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
              to = hosts.jellyfin-nix;
              protocols = [ "tcp" ];
              ports = [ 8096 ];
              comment = "pi-backup to Jellyfin";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.jellyseerr-nix;
              protocols = [ "tcp" ];
              ports = [ 5055 ];
              comment = "pi-backup to Jellyseerr";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.immich-nix;
              protocols = [ "tcp" ];
              ports = [ 2283 ];
              comment = "pi-backup to Immich";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.desktop-nix;
              protocols = [ "tcp" ];
              ports = [ 27017 ];
              comment = "pi-backup to BOIII";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.pufferpanel-nix;
              protocols = [ "tcp" ];
              ports = [ 25565 ];
              comment = "pi-backup to Pufferpanel";
            }
            {
              from = "@host_pi_backup_wireguard";
              to = hosts.gotify-nix;
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
