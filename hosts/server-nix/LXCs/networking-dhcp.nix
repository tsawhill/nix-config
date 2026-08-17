{
  lib,
  networkTopology,
  self,
  ...
}:

let
  inherit (networkTopology.lib) lanIp;
in
{
  imports = [
    ./base
    "${self}/modules/network/dhcp.nix"
  ];

  networking.hostName = "networking-dhcp-nix";

  # A DHCP server cannot lease itself an address, so this is the one container
  # that does not take its IP from the base profile's DHCP client.
  systemd.network.networks."50-eth0".networkConfig = lib.mkForce {
    Address = "${lanIp "networking-dhcp-nix"}/24";
    Gateway = networkTopology.networks.lan.gateway;
    DNS = [ (lanIp networkTopology.networks.lan.dnsHost) ];
  };

  # Flip to true only when OPNsense's LAN DHCP server is switched off; two
  # servers on one broadcast domain race each other.
  my.networking.dhcp.enable = false;
}
