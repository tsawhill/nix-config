{ config, lib, ... }:
{
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.interfaces.eno2.wakeOnLan.enable = true;

  # WireGuard private keys injected into NM profiles via SOPS template
  sops.templates."nm-wireguard-env" = {
    content = ''
      WG_REMOTE_PRIVATE_KEY=${config.sops.placeholder.wg_remote_private_key}
      WG_AIRVPN_PRIVATE_KEY=${config.sops.placeholder.wg_airvpn_private_key}
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

      wg-airvpn = {
        connection = {
          id = "wg-airvpn";
          type = "wireguard";
          interface-name = "wg-airvpn";
          autoconnect = "false";
        };
        wireguard = {
          private-key = "$WG_AIRVPN_PRIVATE_KEY";
        };
        # "wireguard-peer.PEER_PUBLIC_KEY_BASE64=" = {
        #   endpoint = "host:1637";
        #   allowed-ips = "0.0.0.0/0;::/0;";
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
    };
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
