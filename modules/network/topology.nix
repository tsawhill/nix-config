let
  lanDomain = "lan";

  hosts = {
    opnsense = {
      lan.ip = "10.73.73.1";
      dns.enable = true;
    };
    server-nix = {
      lan.ip = "10.73.73.3";
      dns.enable = true;
      monitoring.enable = true;
    };
    netgear-switch = {
      lan = {
        ip = "10.73.73.2";
        mac = "28:80:88:70:5a:b0";
      };
      dns.enable = false;
    };
    samba-nix = {
      lan = {
        ip = "10.73.73.4";
        mac = "bc:24:11:0f:b8:97";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    unbound-vpn-na-nix = {
      lan = {
        ip = "10.73.73.5";
        mac = "a6:1e:69:87:fb:f3";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    adguard-nix = {
      lan = {
        ip = "10.73.73.6";
        mac = "bc:24:11:cd:cd:ec";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    llm-nix = {
      lan = {
        ip = "10.73.73.7";
        mac = "bc:24:11:40:c1:43";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    local-nginx-nix = {
      lan = {
        ip = "10.73.73.8";
        mac = "bc:24:11:42:40:51";
      };
      dns = {
        enable = true;
        aliases = [
          "tsawhill.org"
          "*.tsawhill.org"
        ];
      };
      monitoring.enable = true;
    };
    vaultwarden-nix = {
      lan = {
        ip = "10.73.73.9";
        mac = "bc:24:11:f5:ac:e2";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    acme-nix = {
      lan = {
        ip = "10.73.73.10";
        mac = "bc:24:11:d5:6e:ab";
      };
      dns.enable = false;
    };
    socks5-vpn-eu-nix = {
      lan = {
        ip = "10.73.73.11";
        mac = "bc:24:11:51:dd:4e";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    immich-nix = {
      lan = {
        ip = "10.73.73.12";
        mac = "bc:24:11:de:09:b6";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    arrs-nix = {
      lan = {
        ip = "10.73.73.13";
        mac = "bc:24:11:59:07:12";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    syncthing-nix = {
      lan = {
        ip = "10.73.73.14";
        mac = "10:66:6a:aa:e3:ba";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    jellyfin-nix = {
      lan = {
        ip = "10.73.73.15";
        mac = "bc:24:11:92:d7:50";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    searx-nix = {
      lan = {
        ip = "10.73.73.16";
        mac = "02:ff:b9:66:68:1e";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    nextcloud-nix = {
      lan = {
        ip = "10.73.73.18";
        mac = "bc:24:11:60:3d:cc";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    deluge-nix = {
      lan = {
        ip = "10.73.73.20";
        mac = "bc:24:11:43:7d:c4";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    amcrest-cameras = {
      lan = {
        ip = "10.73.73.21";
      };
      dns.enable = false;
    };
    jellyseerr-nix = {
      lan = {
        ip = "10.73.73.26";
        mac = "bc:24:11:23:f8:93";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    gotify-nix = {
      lan = {
        ip = "10.73.73.27";
        mac = "bc:24:11:2b:3d:4a";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    monitoring-nix = {
      lan = {
        ip = "10.73.73.28";
        mac = "bc:24:11:4d:2c:9f";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    authentik-nix = {
      lan = {
        ip = "10.73.73.29";
        mac = "8e:95:4f:6e:c7:13";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    pufferpanel-nix = {
      lan = {
        ip = "10.73.73.30";
        mac = "bc:24:11:9d:2b:70";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    homepage-nix = {
      lan = {
        ip = "10.73.73.32";
        mac = "bc:24:11:7a:e0:14";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    build-nix = {
      lan = {
        ip = "10.73.73.40";
        mac = "bc:24:11:e1:63:a2";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    unifi-nix = {
      lan = {
        ip = "10.73.73.41";
        mac = "bc:24:11:50:c5:51";
      };
      dns.enable = true;
      # Only powered on to change settings, so scraping it would just show a
      # permanently down exporter. Flip to true if it becomes always-on.
      monitoring.enable = false;
    };
    pi-backup-nix = {
      lan = {
        ip = "10.73.73.42";
        mac = "88:a2:9e:77:6d:8b";
      };
      wgRemote.ip = "10.50.50.5";
      dns = {
        enable = true;
        preferredAddress = "wgRemote";
      };
    };
    taylor-laptop-nix = {
      lan = {
        ip = "10.73.73.68";
        mac = "b0:dc:ef:20:5c:ba";
      };
      wgRemote.ip = "10.50.50.3";
      dns = {
        enable = true;
        roaming = true;
      };
    };
    taylor-desktop-nix = {
      lan = {
        ip = "10.73.73.69";
        mac = "c8:7f:54:6c:e2:96";
      };
      wgRemote.ip = "10.50.50.2";
      dns = {
        enable = true;
        roaming = true;
      };
    };
    printer = {
      lan = {
        ip = "10.73.73.71";
        mac = "38:7a:cc:42:d1:de";
      };
      dns.enable = true;
    };
    taylor-deck-nix = {
      lan = {
        ip = "10.73.73.73";
        mac = "b4:8c:9d:7e:6d:73";
      };
      wgRemote.ip = "10.50.50.4";
      dns = {
        enable = true;
        roaming = true;
      };
    };
    taylor-cube-nix = {
      lan = {
        ip = "10.73.73.74";
        # Wi-Fi NIC (wlp6s0). Ethernet (enp5s0, 90:82:c3:6b:8e:69) is currently
        # unplugged; swap this MAC if the cube moves to a wired link.
        mac = "ec:b5:0a:e7:24:7c";
      };
      wgRemote.ip = "10.50.50.6";
      dns = {
        enable = true;
        roaming = true;
      };
    };
    sunshine-nix = {
      lan = {
        ip = "10.73.73.140";
        mac = "02:7d:da:73:cc:0d";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
    remote-nginx-nix = {
      wgRemote.ip = "10.50.50.16";
      dns = {
        enable = true;
        preferredAddress = "wgRemote";
      };
    };
    # NixOS replacement for remote-nginx-nix on an OCI A1.Flex (aarch64).
    # Deliberately given its own tunnel address rather than reusing .16 so the
    # two can run side by side during cutover. Once traffic is moved, drop the
    # remote-nginx-nix entry above.
    oracle-1-nix = {
      wgRemote.ip = "10.50.50.17";
      dns = {
        enable = true;
        preferredAddress = "wgRemote";
      };
    };
    pixel7pro.wgRemote.ip = "10.50.50.11";
    palworld-nix = {
      lan = {
        ip = "10.73.73.31";
        mac = "02:36:bc:73:0d:3b";
      };
      dns.enable = true;
      monitoring.enable = true;
    };
  };

  fqdn = host: "${host}.${lanDomain}";
  lanIp = host: hosts.${host}.lan.ip;
  wgIp = host: hosts.${host}.wgRemote.ip;
  dnsAnswer =
    host:
    let
      entry = hosts.${host};
      preferred =
        entry.dns.preferredAddress or (if entry.dns.roaming or false then "wgRemote" else "lan");
    in
    if preferred == "wgRemote" then entry.wgRemote.ip else entry.lan.dnsIp or entry.lan.ip;
in
{
  domains = {
    lan = lanDomain;
    dhcp = "home.arpa";
  };

  networks = {
    lan = {
      cidr = "10.73.73.0/24";
      gateway = hosts.opnsense.lan.ip;
      dnsHost = "adguard-nix";
      dhcpPool = {
        start = "10.73.73.100";
        end = "10.73.73.245";
      };
    };
    wgRemote = {
      cidr = "10.50.50.0/24";
      routedCidr = "10.50.0.0/16";
      routerAddress = "10.50.50.1";
      endpoint = "taylordnsfree.zapto.org";
      port = 51820;
    };
  };

  inherit hosts;

  lib = {
    inherit
      dnsAnswer
      fqdn
      lanIp
      wgIp
      ;
    wgAddress = host: "${wgIp host}/32";
  };
}
