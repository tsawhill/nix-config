{ lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;

  # One logical L3 interface. The key is intentionally not assumed to be the
  # Linux device name, so callers can use stable names like "lan" or "guest".
  interfaceType = types.submodule (
    { name, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Linux interface name.";
        };

        role = mkOption {
          type = types.enum [
            "lan"
            "wan"
            "internal"
            "vpn"
          ];
          description = "Router role for this interface.";
        };

        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "IPv4 address assigned to this interface.";
        };

        prefixLength = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "IPv4 prefix length for address.";
        };

        dhcpClient = mkOption {
          type = types.bool;
          default = false;
          description = "Whether this interface should obtain IPv4 configuration with DHCP.";
        };

        requiredForOnline = mkOption {
          type = types.str;
          default = "routable";
          description = "systemd-networkd RequiredForOnline value.";
        };

        # DHCP is interface-scoped so multiple LANs/VLANs can each own their
        # pool, reservations, DNS, and gateway without a separate cross-map.
        dhcp = {
          enable = mkEnableOption "Kea DHCPv4 service on this interface";

          subnet = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "DHCP subnet in CIDR form, e.g. 192.0.2.0/24.";
          };

          rangeStart = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "First address in the DHCP pool.";
          };

          rangeEnd = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Last address in the DHCP pool.";
          };

          gateway = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Gateway advertised to DHCP clients.";
          };

          dnsServers = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "DNS servers advertised to DHCP clients.";
          };

          domain = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Domain name advertised to DHCP clients.";
          };

          reservations = mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  mac = mkOption { type = types.str; };
                  ip = mkOption { type = types.str; };
                  hostname = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                  description = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                };
              }
            );
            default = [ ];
            description = "Static DHCP reservations for this interface.";
          };
        };
      };
    }
  );

  # Shared peer shape for both server peers and provider/client peers.
  peerType = types.submodule {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Peer public key (literal). Mutually exclusive with publicKeyFile.";
      };
      publicKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing peer public key. Used with systemd-networkd PublicKeyFile.";
      };
      allowedIPs = mkOption { type = types.listOf types.str; };
      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      persistentKeepalive = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      presharedKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  policyRuleType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      source = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      destination = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      mark = mkOption { type = types.int; };
      comment = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  portForwardType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      inInterface = mkOption { type = types.str; };
      protocols = mkOption {
        type = types.listOf (types.enum [
          "tcp"
          "udp"
        ]);
        default = [
          "tcp"
          "udp"
        ];
      };
      originalPort = mkOption { type = types.int; };
      destination = mkOption { type = types.str; };
      destinationPort = mkOption { type = types.int; };
    };
  };

  blockRuleType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      inInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      source = mkOption { type = types.str; };
      destination = mkOption {
        type = types.str;
        default = "0.0.0.0/0";
      };
    };
  };

  addressMatcherType = types.oneOf [
    types.str
    (types.listOf types.str)
  ];

  forwardRuleType = types.submodule {
    options = {
      from = mkOption {
        type = addressMatcherType;
        default = "any";
        description = ''
          Source IPv4 matcher. Use "any" for no source match, "@alias" for a
          firewall alias, a single address/CIDR, or a list of addresses.
        '';
      };

      to = mkOption {
        type = addressMatcherType;
        default = "any";
        description = ''
          Destination IPv4 matcher. Prefix a single value with "!" to express
          "not this destination", for example "!@local_addresses".
        '';
      };

      protocols = mkOption {
        type = types.listOf (types.enum [
          "tcp"
          "udp"
        ]);
        default = [ ];
        description = "Protocols matched by this rule. Empty means any protocol.";
      };

      ports = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "Destination ports matched by this rule. Empty means any port.";
      };

      outInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional egress interface matcher.";
      };

      comment = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Human-readable rule label.";
      };
    };
  };

  interfaceRulesType = types.submodule {
    options = {
      allow = mkOption {
        type = types.listOf forwardRuleType;
        default = [ ];
        description = ''
          Ordered pass rules for traffic entering this interface. Rules are
          emitted top-to-bottom, matching the way firewall policy pages are read.
        '';
      };

      block = mkOption {
        type = types.listOf forwardRuleType;
        default = [ ];
        description = ''
          Ordered block rules for traffic entering this interface. These are
          emitted before allow rules for the same interface.
        '';
      };
    };
  };

  policyRouteType = types.submodule {
    options = {
      from = mkOption {
        type = addressMatcherType;
        default = "any";
        description = "Source matcher for traffic that should use a policy-routed tunnel.";
      };

      to = mkOption {
        type = addressMatcherType;
        default = "any";
        description = "Destination matcher. Prefix a single value with ! for negation.";
      };

      via = mkOption {
        type = types.str;
        description = "WireGuard client name whose fwMark should be applied.";
      };

      comment = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Human-readable policy route label.";
      };
    };
  };
in
{
  options.my.router = {
    enable = mkEnableOption "reusable NixOS router module";

    interfaces = mkOption {
      type = types.attrsOf interfaceType;
      default = { };
      description = "Router interfaces keyed by logical name.";
    };

    wireguard = {
      servers = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              address = mkOption { type = types.str; };
              listenPort = mkOption { type = types.port; };
              privateKeyFile = mkOption { type = types.str; };
              mtu = mkOption {
                type = types.nullOr types.int;
                default = null;
              };
              peers = mkOption {
                type = types.listOf peerType;
                default = [ ];
              };
            };
          }
        );
        default = { };
      };

      clients = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              address = mkOption { type = types.str; };
              privateKeyFile = mkOption { type = types.str; };
              publicKey = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Peer public key (literal). Mutually exclusive with publicKeyFile.";
              };
              publicKeyFile = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Path to file containing peer public key.";
              };
              presharedKeyFile = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
              endpoint = mkOption { type = types.str; };
              allowedIPs = mkOption {
                type = types.listOf types.str;
                default = [ "0.0.0.0/0" ];
              };
              persistentKeepalive = mkOption {
                type = types.nullOr types.int;
                default = 15;
              };
              mtu = mkOption {
                type = types.nullOr types.int;
                default = null;
              };
              gateway = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
              fwMark = mkOption {
                type = types.nullOr types.int;
                default = null;
              };
              routeTable = mkOption {
                type = types.nullOr types.int;
                default = null;
              };
              routePriority = mkOption {
                type = types.int;
                default = 10000;
              };
            };
          }
        );
        default = { };
      };
    };

    firewall = {
      aliases = mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                name = mkOption {
                  type = types.str;
                  default = name;
                };
                nftType = mkOption {
                  type = types.str;
                  default = "ipv4_addr";
                };
                values = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };
              };
            }
          )
        );
        default = { };
      };

      allowedWan = {
        tcp = mkOption {
          type = types.listOf types.port;
          default = [ ];
        };
        udp = mkOption {
          type = types.listOf types.port;
          default = [ ];
        };
      };

      blockForward = mkOption {
        type = types.listOf blockRuleType;
        default = [ ];
      };

      # Higher-level forward policy keyed by ingress interface. This is the
      # preferred shape for host config because the generated nftables stays
      # hidden and the list order remains visible in the consumer.
      rules = mkOption {
        type = types.attrsOf interfaceRulesType;
        default = { };
        description = "Ordered allow/block rules keyed by ingress interface name.";
      };

      policyRules = mkOption {
        type = types.listOf policyRuleType;
        default = [ ];
      };

      # Policy routing is the readable form of nftables mangle mark rules. The
      # module looks up the selected WireGuard client's fwMark and writes the
      # backend rule, so private config can say "via wg-airvpn-na".
      policyRoutes = mkOption {
        type = types.listOf policyRouteType;
        default = [ ];
        description = "Ordered policy-routing rules that mark traffic for a WireGuard client.";
      };

      portForwards = mkOption {
        type = types.listOf portForwardType;
        default = [ ];
      };

      masqueradeInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      extraInputRules = mkOption {
        type = types.lines;
        default = "";
      };

      extraEarlyForwardRules = mkOption {
        type = types.lines;
        default = "";
        description = "Additional forward-chain rules evaluated before broad LAN allow rules.";
      };

      extraForwardRules = mkOption {
        type = types.lines;
        default = "";
      };

      extraPreroutingRules = mkOption {
        type = types.lines;
        default = "";
      };

      extraPostroutingRules = mkOption {
        type = types.lines;
        default = "";
      };

      extraMangleRules = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };
}
