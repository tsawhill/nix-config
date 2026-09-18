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
  # [Interface] Address from this device's own WireGuard config. Per-device, so
  # it cannot be copied from another gateway.
  tunnelAddress = "";
  inherit (networkTopology.lib) lanIp;
in
{
  imports = [
    ./base
    "${self}/modules/network/networkmanager/wireguard/routable-airvpn.nix"
  ];

  assertions = [
    {
      assertion = !vpnEnabled || tunnelAddress != "";
      message = "Set the AirVPN device [Interface] Address before enabling the EU gateway.";
    }
  ];
  networking.hostName = "networking-vpn-out-eu1-nix";
  # Also needed during bootstrap, before routableAirvpn.enable is set.
  networking.wireless.enable = lib.mkForce false;
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

  my.secrets."networking-vpn-out-eu1-nix".enable = vpnEnabled;
  my.secrets.deluge-vpn.enable = vpnEnabled;
  my.network.routableAirvpn = {
    enable = vpnEnabled;
    address = tunnelAddress;
    countries = [ "CH" ];
    # AirVPN shares one server key across all endpoints; na1 uses this same key
    # for four cities. Confirm it against the downloaded CH config anyway.
    peerPublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
    privateKeySecret = "vpn_egress_wireguard_private_key";
    presharedKeySecret = "vpn_egress_wireguard_preshared_key";

    clientAddresses = [
      (lanIp "deluge-nix")
    ];
    lanCidr = networkTopology.networks.lan.cidr;
    upstreamGateway = networkTopology.networks.lan.gateway;
    bypassRoutes = [
      {
        cidr = networkTopology.networks.wgRemote.routedCidr;
        gateway = networkTopology.networks.lan.gateway;
      }
    ];

    portForwards = [
      {
        portSecret = "deluge_vpn_port";
        destinationAddress = lanIp "deluge-nix";
      }
    ];

    gotifyUrl = "https://gotify.tsawhill.org/message";
  }
  // lib.optionalAttrs vpnEnabled {
    gotifyTokenFile = config.sops.secrets.vpn_egress_gotify_token.path;
  };
}
