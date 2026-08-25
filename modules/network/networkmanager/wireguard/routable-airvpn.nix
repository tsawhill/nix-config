{
  config,
  lib,
  ...
}:

let
  cfg = config.my.network.routableAirvpn;
in
{
  imports = [
    ./airvpn.nix
    ../../vpn-egress-gateway.nix
  ];

  options.my.network.routableAirvpn = {
    enable = lib.mkEnableOption "a routable AirVPN gateway using NetworkManager profiles";

    address = lib.mkOption {
      type = lib.types.str;
      description = "AirVPN-assigned tunnel IPv4 address with prefix.";
    };

    countries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "AirVPN countries whose NetworkManager profiles should be generated.";
    };

    cities = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "AirVPN cities whose NetworkManager profiles should be generated.";
    };

    servers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Individual AirVPN servers whose NetworkManager profiles should be generated.";
    };

    autoconnect = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional AirVPN server profile to activate automatically.";
    };

    enableWireless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether NetworkManager should also start a Wi-Fi backend on the gateway.";
    };

    peerPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "Public key of the AirVPN peer for this dedicated device profile.";
    };

    privateKeySecret = lib.mkOption {
      type = lib.types.str;
      description = "SOPS secret name containing the dedicated AirVPN private key.";
    };

    presharedKeySecret = lib.mkOption {
      type = lib.types.str;
      description = "SOPS secret name containing the dedicated AirVPN preshared key.";
    };

    clientAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "LAN IPv4 addresses authorized to use this gateway.";
    };

    remoteTriggers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            source = lib.mkOption {
              type = lib.types.str;
              description = "Source address allowed to use this trigger key.";
            };
            publicKey = lib.mkOption {
              type = lib.types.str;
              description = "Full SSH public key for this restricted trigger client.";
            };
            allowedReasons = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Exact rotation reasons this key may request.";
            };
          };
        }
      );
      default = [ ];
      description = "Source- and key-restricted endpoint-rotation clients.";
    };

    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "LAN interface carrying client and AirVPN endpoint traffic.";
    };

    upstreamGateway = lib.mkOption {
      type = lib.types.str;
      description = "Normal LAN gateway used by explicitly bypassed routes.";
    };

    lanCidr = lib.mkOption {
      type = lib.types.str;
      description = "Directly connected LAN CIDR retained outside the VPN tunnel.";
    };

    bypassRoutes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            cidr = lib.mkOption { type = lib.types.str; };
            gateway = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = "Additional networks routed through the normal LAN gateway.";
    };

    routingTable = lib.mkOption {
      type = lib.types.int;
      default = 51820;
      description = "Policy-routing table used for VPN clients and leak prevention.";
    };

    gotifyUrl = lib.mkOption {
      type = lib.types.str;
      description = "Gotify message endpoint used for recovery and failure notifications.";
    };

    gotifyTokenFile = lib.mkOption {
      type = lib.types.coercedTo lib.types.path toString lib.types.str;
      description = "Runtime file containing the dedicated Gotify application token.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = true;
    # NetworkManager enables wpa_supplicant by default even on wired-only
    # systems. Containers do not have /dev/rfkill, so keep that service out of
    # the activation transaction unless this gateway explicitly needs Wi-Fi.
    networking.wireless.enable = lib.mkForce cfg.enableWireless;

    my.network.airvpn = {
      enable = true;
      inherit (cfg)
        address
        autoconnect
        cities
        countries
        peerPublicKey
        privateKeySecret
        presharedKeySecret
        servers
        ;
      allowedIPs = "0.0.0.0/0;";
      dns = null;
      peerRoutes = false;
      neverDefault = true;
      routeTable = cfg.routingTable;
    };

    my.network.vpnEgress.gateway = {
      enable = true;
      inherit (cfg)
        bypassRoutes
        clientAddresses
        gotifyTokenFile
        gotifyUrl
        lanCidr
        remoteTriggers
        routingTable
        upstreamGateway
        upstreamInterface
        ;
    };
  };
}
