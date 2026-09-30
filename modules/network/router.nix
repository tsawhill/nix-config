{
  config,
  lib,
  networkTopology,
  ...
}:

let
  cfg = config.my.network.router;
  inherit (networkTopology) zones;
  inherit (networkTopology.lib) lanIp;
  lan = networkTopology.networks.lan;

  policy = import ./firewall/router.nix;
  up = cfg.upstreamInterface;
  zoneNames = lib.attrNames zones;
  policyZones = zoneNames ++ [
    "legacy"
    "internet"
  ];
  prefixOf = cidr: lib.last (lib.splitString "/" cidr);
  quoted = names: lib.concatMapStringsSep ", " (name: ''"${name}"'') names;

  # Legacy and internet share the upstream link until the WAN moves here.
  fromZone = zone: if zone == "legacy" then ''iifname "${up}"'' else ''iifname "${zone}"'';
  toZone =
    zone:
    if zone == "legacy" then
      ''oifname "${up}" ip daddr @private''
    else if zone == "internet" then
      ''oifname "${up}" ip daddr != @private''
    else
      ''oifname "${zone}"'';

  zoneRules = lib.concatLists (
    lib.mapAttrsToList (from: map (to: "${fromZone from} ${toZone to} accept")) policy.allow
  );
  hostRules = map (rule: "ip saddr ${lanIp rule.host} ${toZone rule.to} accept") policy.hostAllow;
  referencedZones = lib.attrNames policy.allow ++ lib.concatLists (lib.attrValues policy.allow);
in
{
  options.my.network.router = {
    enable = lib.mkEnableOption "the inter-zone router for the VLAN zones in the topology";

    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
    };

    dhcpServer = lib.mkOption {
      type = lib.types.str;
      default = lanIp "networking-dhcp-nix";
      description = "Kea address that zone DHCP requests are relayed to.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (zone: lib.elem zone policyZones) (
          referencedZones ++ map (rule: rule.to) policy.hostAllow
        );
        message = "firewall/router.nix names a zone that isn't in topology.zones, legacy or internet.";
      }
    ];

    systemd.network = {
      netdevs = lib.mapAttrs' (
        name: zone:
        lib.nameValuePair "60-${name}" {
          netdevConfig = {
            Kind = "vlan";
            Name = name;
          };
          vlanConfig.Id = zone.vlan;
        }
      ) zones;

      networks = {
        "50-eth0".networkConfig.VLAN = zoneNames;
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
            set private {
              type ipv4_addr
              flags interval
              elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
            }

            chain input {
              type filter hook input priority filter; policy drop;
              iifname "lo" accept
              ct state established,related accept
              ct state invalid drop
              ip protocol icmp accept
              iifname "${up}" ip saddr ${lan.cidr} tcp dport { 22, 9100, 9558 } accept
              iifname "trusted" tcp dport 22 accept
              # DHCP relay: requests from the zones, answers from Kea
              iifname { ${quoted zoneNames} } udp dport 67 accept
              iifname "${up}" ip saddr ${cfg.dhcpServer} udp dport 67 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
              ct state established,related accept
              ct state invalid drop
              ip daddr ${lanIp lan.dnsHost} meta l4proto { tcp, udp } th dport 53 accept
              ${lib.concatStringsSep "\n              " (zoneRules ++ hostRules)}
            }
          '';
        };
      };
    };
  };
}
