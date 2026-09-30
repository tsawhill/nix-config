{
  config,
  lib,
  networkTopology,
  self,
  ...
}:

let
  cfg = config.my.network.router;
  inherit (networkTopology) zones hosts;
  inherit (networkTopology.lib) lanIp;
  lan = networkTopology.networks.lan;
  transit = networkTopology.networks.vpnInTransit;
  wgRemote = networkTopology.networks.wgRemote;

  policy = import ./firewall/router.nix;

  # VPN egress clients never use the WAN; this backs up their own routing.
  egressClients = lib.filter (
    name:
    self.nixosConfigurations ? ${name}
    && (self.nixosConfigurations.${name}.config.my.network.vpnEgress.client.enable or false)
  ) (lib.attrNames hosts);
  noInternet = policy.noInternet ++ egressClients;
  zoneNames = lib.attrNames zones;
  prefixOf = cidr: lib.last (lib.splitString "/" cidr);
  quoted = names: lib.concatMapStringsSep ", " (name: ''"${name}"'') names;

  addressOf =
    host:
    if (hosts.${host}.attachment or "lan") == "transit" then
      hosts.${host}.transit.ip
    else
      hosts.${host}.lan.ip;

  # Policy zone -> interface. Zone VLAN interfaces are named after their zone.
  interfaces = {
    legacy = "eth0";
    vpn = "transit";
    internet = "wan";
  }
  // lib.genAttrs zoneNames (name: name);

  zoneRules = lib.concatLists (
    lib.mapAttrsToList (
      from: map (to: ''iifname "${interfaces.${from}}" oifname "${interfaces.${to}}" accept'')
    ) policy.allow
  );
  hostRules = map (
    rule: ''ip saddr ${addressOf rule.host} oifname "${interfaces.${rule.to}}" accept''
  ) policy.hostAllow;
  forwardRules = map (
    fwd:
    "fib daddr type local ${fwd.protocol} dport ${toString fwd.port} dnat ip to ${addressOf fwd.host}"
  ) policy.portForwards;

  referencedZones =
    lib.attrNames policy.allow
    ++ lib.concatLists (lib.attrValues policy.allow)
    ++ map (rule: rule.to) policy.hostAllow;

  # Down until the takeover, so nothing clashes with OPNsense on br1/br2.
  standbyLink = {
    RequiredForOnline = "no";
  }
  // lib.optionalAttrs (!cfg.takeover) { ActivationPolicy = "down"; };
in
{
  options.my.network.router = {
    enable = lib.mkEnableOption "the router, NAT and inter-zone firewall that replaces OPNsense";

    takeover = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Take over from OPNsense: 10.73.73.1 on the LAN, the WAN and the vpn-in transit.
        Only flip this with the OPNsense VM stopped.
      '';
    };

    dhcpServer = lib.mkOption {
      type = lib.types.str;
      default = lanIp "networking-dhcp-nix";
      description = "Kea address that zone DHCP requests are relayed to.";
    };

    wanMacAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        MAC the WAN link takes on at takeover, so the ISP keeps the same lease.
        Set here rather than in Incus, which refuses a MAC another NIC already has.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (zone: interfaces ? ${zone}) referencedZones;
        message = "firewall/router.nix names a zone that isn't in topology.zones, legacy, vpn or internet.";
      }
    ];

    systemd.network = {
      # Each zone is its own Incus NIC with the VLAN set on br0: VLAN netdevs made
      # inside the LXC stay pending forever because udev never initialises them.
      networks = {
        "50-eth0" = {
          # The default route comes from the WAN lease instead.
          networkConfig = lib.optionalAttrs cfg.takeover { Gateway = lib.mkForce [ ]; };
          # ACD leaves the address off if OPNsense still answers for it.
          addresses = lib.optional cfg.takeover {
            Address = "${lan.gateway}/${prefixOf lan.cidr}";
            DuplicateAddressDetection = "ipv4";
          };
        };

        "60-wan" = {
          matchConfig.Name = "wan";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
          # Same MAC and client ID as OPNsense, so the ISP keeps handing out the same lease.
          dhcpV4Config = {
            ClientIdentifier = "mac";
            UseDNS = false;
          };
          linkConfig =
            standbyLink
            // lib.optionalAttrs (cfg.takeover && cfg.wanMacAddress != null) {
              MACAddress = cfg.wanMacAddress;
            };
        };

        "60-transit" = {
          matchConfig.Name = "transit";
          networkConfig = {
            Address = "${transit.gateway}/${prefixOf transit.cidr}";
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          routes = [
            {
              Destination = wgRemote.routedCidr;
              Gateway = addressOf "networking-vpn-in-nix";
            }
          ];
          linkConfig = standbyLink;
        };
      }
      // lib.mapAttrs' (
        name: zone:
        lib.nameValuePair "60-${name}" {
          matchConfig.Name = name;
          networkConfig = {
            Address = "${zone.gateway}/${prefixOf zone.cidr}";
            DHCPServer = true;
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
            ConfigureWithoutCarrier = true;
          };
          dhcpServerConfig.RelayTarget = cfg.dhcpServer;
          linkConfig.RequiredForOnline = "no";
        }
      ) zones;
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
    };

    networking = {
      firewall.enable = false;
      nftables = {
        enable = true;
        tables.router = {
          family = "inet";
          content = ''
            set no_internet {
              type ipv4_addr
              ${lib.optionalString (noInternet != [ ])
                "elements = { ${lib.concatMapStringsSep ", " addressOf noInternet} }"
              }
            }

            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;
              ${lib.concatStringsSep "\n              " forwardRules}
            }

            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "wan" masquerade
            }

            chain input {
              type filter hook input priority filter; policy drop;
              iifname "lo" accept
              ct state established,related accept
              ct state invalid drop
              ip protocol icmp accept
              iifname "eth0" ip saddr ${lan.cidr} tcp dport { 22, 9100, 9558 } accept
              iifname "trusted" tcp dport 22 accept
              iifname "wan" udp sport 67 udp dport 68 accept
              # DHCP relay: requests from the zones, answers from Kea
              iifname { ${quoted zoneNames} } udp dport 67 accept
              iifname "eth0" ip saddr ${cfg.dhcpServer} udp dport 67 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
              ct state established,related accept
              ct state invalid drop
              ct status dnat accept
              ip saddr @no_internet oifname "wan" drop
              ip daddr ${lanIp lan.dnsHost} meta l4proto { tcp, udp } th dport 53 accept
              ${lib.concatStringsSep "\n              " (zoneRules ++ hostRules)}
            }
          '';
        };
      };
    };
  };
}
