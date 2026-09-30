{
  lib,
  self,
  networkTopology,
  ...
}:

let
  # Leave false for the factory run. After the factory adds this host's age
  # recipient, create the server key secret, rekey pubkeys.yaml, then flip this.
  wgEnabled = false;

  host = networkTopology.hosts.networking-vpn-in-nix;
  transit = networkTopology.networks.vpnInTransit;
  onTransit = host.attachment == "transit";
  transitPrefix = lib.last (lib.splitString "/" transit.cidr);
in
{
  imports = [
    ./base
    "${self}/modules/network/wg-remote-server.nix"
  ];

  networking.hostName = "networking-vpn-in-nix";

  my.secrets.wireguard.networking-vpn-in-nix.wg-remote-server.enable = wgEnabled;
  my.network.wgRemoteServer.enable = wgEnabled;

  # Only on the transit bridge; being on the LAN too would let replies skip the router.
  systemd.network.networks."50-eth0".networkConfig = lib.mkIf onTransit {
    Address = lib.mkForce "${host.transit.ip}/${transitPrefix}";
    Gateway = lib.mkForce transit.gateway;
  };
}
