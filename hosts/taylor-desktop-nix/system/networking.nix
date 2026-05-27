{ self, config, lib, ... }:

let
  airvpn = import "${self}/modules/network/wireguard/airvpn-servers.nix";

  # Select AirVPN servers by country code, city name, or server name.
  # All three lists are combined with OR logic.
  airvpnCountries = [ "US" "CA" ];
  airvpnCities = [ ];
  airvpnServers = [ ];

  selectedServers = lib.filterAttrs (
    name: srv:
    builtins.elem srv.country airvpnCountries
    || builtins.elem srv.city airvpnCities
    || builtins.elem name airvpnServers
  ) airvpn.servers;

  mkAirvpnProfile = name: srv: {
    connection = {
      id = "wg-airvpn-${name}";
      type = "wireguard";
      interface-name = "wg-airvpn";
      autoconnect = "false";
    };
    wireguard = {
      private-key = "$WG_AIRVPN_PRIVATE_KEY";
    };
    "wireguard-peer.${airvpn.publicKey}" = {
      preshared-key = "$WG_AIRVPN_PRESHARED_KEY";
      endpoint = "${srv.ip}:${toString airvpn.port}";
      allowed-ips = "0.0.0.0/0;::/0;";
      persistent-keepalive = "15";
    };
    ipv4 = {
      method = "manual";
      # address1 = "10.x.x.x/32"; # Set to your AirVPN device address
      dns = "${airvpn.dns.ipv4};";
    };
    ipv6 = {
      method = "disabled";
    };
  };

  airvpnProfiles = lib.mapAttrs' (
    name: srv: lib.nameValuePair "wg-airvpn-${name}" (mkAirvpnProfile name srv)
  ) selectedServers;
in
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.interfaces.eno2.wakeOnLan.enable = true;

  # WireGuard secrets injected into NM profiles via SOPS template
  sops.templates."nm-wireguard-env" = {
    content = ''
      WG_REMOTE_PRIVATE_KEY=${config.sops.placeholder.wg_remote_private_key}
      WG_AIRVPN_PRIVATE_KEY=${config.sops.placeholder.wg_airvpn_private_key}
      WG_AIRVPN_PRESHARED_KEY=${config.sops.placeholder.wg_airvpn_preshared_key}
    '';
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [
      config.sops.templates."nm-wireguard-env".path
    ];

    profiles = {
      wg-remote = {
        connection = {
          id = "wg-remote";
          type = "wireguard";
          interface-name = "wg-remote";
          autoconnect = "false";
        };
        wireguard = {
          private-key = "$WG_REMOTE_PRIVATE_KEY";
        };
        # "wireguard-peer.PEER_PUBLIC_KEY_BASE64=" = {
        #   endpoint = "host:51820";
        #   allowed-ips = "10.0.0.0/24;";
        #   persistent-keepalive = "25";
        # };
        ipv4 = {
          method = "manual";
          # address1 = "10.x.x.x/32";
        };
        ipv6 = {
          method = "disabled";
        };
      };
    } // airvpnProfiles;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
        DiscoverableTimeout = 0;
      };
    };
  };

  services.blueman.enable = true;
}
