{
  config,
  lib,
  networkTopology,
  self,
  ...
}:

let
  settings = import ./vpn-eu-settings.nix;
  vpnEnabled = settings.gatewayEnable;
  inherit (networkTopology.lib) lanIp;
in
{
  imports = [
    ./base
    "${self}/modules/network/networkmanager/wireguard/routable-airvpn.nix"
  ];

  assertions = [
    {
      assertion = !vpnEnabled || settings.peerPublicKey != "";
      message = "Set the AirVPN [Peer] PublicKey before enabling the EU gateway.";
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
    address = "10.169.2.22/32";
    countries = [ "CH" ];
    peerPublicKey = settings.peerPublicKey;
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
