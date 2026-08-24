{
  config,
  lib,
  networkTopology,
  self,
  ...
}:

let
  # Provisioning is deliberately two-stage. Leave this false for the factory
  # run; after the factory adds this host's age recipient, create its SOPS file,
  # fill in tunnelAddress below, and flip this to true.
  vpnEnabled = false;
  inherit (networkTopology.lib) lanIp;
in
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-gateway.nix"
  ];

  networking.hostName = "networking-vpn-out-na1-nix";

  my.secrets."networking-vpn-out-na1-nix".enable = vpnEnabled;
  my.network.vpnEgress.gateway = {
    enable = vpnEnabled;

    # Fill this with the IPv4 Interface/Address from the dedicated AirVPN
    # WireGuard profile before enabling the gateway.
    tunnelAddress = null;
    # AirVPN currently uses this peer key across the existing device profiles;
    # verify it against the dedicated profile before enabling.
    peerPublicKey = "wwxzv1Fsw6egiLmJuwFKxqFD0lVwQrUKVnq+NmsXG20=";

    clientAddresses = [ (lanIp "searx-nix") ];
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

    gotifyUrl = "https://gotify.tsawhill.org/message";
  }
  // lib.optionalAttrs vpnEnabled {
    privateKeyFile = config.sops.secrets.vpn_egress_wireguard_private_key.path;
    presharedKeyFile = config.sops.secrets.vpn_egress_wireguard_preshared_key.path;
    gotifyTokenFile = config.sops.secrets.vpn_egress_gotify_token.path;
  };
}
