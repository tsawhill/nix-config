{
  config,
  lib,
  networkTopology,
  self,
  ...
}:

let
  vpnEnabled = true;
  inherit (networkTopology.lib) lanIp;
in
{
  imports = [
    ./base
    "${self}/modules/network/networkmanager/wireguard/routable-airvpn.nix"
  ];

  networking.hostName = "networking-vpn-out-na1-nix";
  systemd.network.enable = lib.mkForce false;
  networking.networkmanager = {
    enable = true;
    ensureProfiles.profiles.lan = {
      connection = {
        id = "lan";
        type = "ethernet";
        interface-name = "eth0";
        autoconnect = "true";
      };
      ipv4.method = "auto";
      ipv6.method = "disabled";
    };
  };

  my.secrets."networking-vpn-out-na1-nix".enable = vpnEnabled;
  my.network.routableAirvpn = {
    enable = vpnEnabled;
    address = "10.168.141.96/32";
    cities = [
      "Fremont-California"
      "LosAngeles"
      "Phoenix-Arizona"
      "SanJose-California"
    ];
    peerPublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
    privateKeySecret = "vpn_egress_wireguard_private_key";
    presharedKeySecret = "vpn_egress_wireguard_preshared_key";

    clientAddresses = [
      (lanIp "searx-nix")
      (lanIp "unbound-vpn-na-nix")
    ];
    lanCidr = networkTopology.networks.lan.cidr;
    upstreamGateway = networkTopology.networks.lan.gateway;
    bypassRoutes = [
      {
        cidr = networkTopology.networks.wgRemote.routedCidr;
        gateway = networkTopology.networks.lan.gateway;
      }
    ];

    # Reuse searx-nix's SSH host key as a client identity. The forced-key
    # restrictions on this gateway allow exactly one enumerated rotation action
    # from searx-nix's LAN address and do not grant an interactive root shell.
    remoteTriggers = [
      {
        source = lanIp "searx-nix";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEkQnFXTyn5xJS70NwfnCyMnDfUyNF/c+8DZw94dd0MD searx-nix-host-key";
        allowedReasons = [ "searx-startpage-blocked" ];
      }
    ];
    blockedExitReasons = [ "searx-startpage-blocked" ];

    gotifyUrl = "https://gotify.tsawhill.org/message";
  }
  // lib.optionalAttrs vpnEnabled {
    gotifyTokenFile = config.sops.secrets.vpn_egress_gotify_token.path;
  };
}
