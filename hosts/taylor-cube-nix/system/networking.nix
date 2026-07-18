{ networkTopology, ... }:

let
  inherit (networkTopology.lib) lanIp wgAddress;
  wgRemote = networkTopology.networks.wgRemote;
  wgEndpoint = "${wgRemote.endpoint}:${toString wgRemote.port}";
  wgAllowedIPs = "${wgRemote.cidr};${networkTopology.networks.lan.cidr};";
in
{
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # WireGuard tunnel back to the home network. allowedIPs cover the LAN and the
  # remote WG subnet so LAN services resolve when the cube is off-site.
  my.secrets.wireguard.pubkeys.enable = true;
  my.network.networkmanager.wifi = {
    enable = true;
    defaultMacAddress = networkTopology.hosts.taylor-cube-nix.lan.mac;
  };

  my.network.wg-remote = {
    enable = true;
    address = wgAddress "taylor-cube-nix";
    autoconnect = "true";
    dns = lanIp networkTopology.networks.lan.dnsHost;
    dnsPriority = 50;
    routeMetric = 50000;
    peer = {
      endpoint = wgEndpoint;
      allowedIPs = wgAllowedIPs;
    };
  };

  # AirVPN (disabled). To enable:
  #   1. Generate a WireGuard config for this device in the AirVPN client area.
  #   2. Create modules/secrets/wireguard/taylor-cube-nix/wg-airvpn.yaml with
  #      private_key + preshared_key (see sops templates in the setup notes).
  #   3. Enable the secret in hosts/taylor-cube-nix/default.nix
  #      (my.secrets.wireguard.taylor-cube-nix.wg-airvpn.enable = true).
  #   4. Set `address` to the AirVPN-assigned tunnel IP and pick a server below.
  # my.network.airvpn = {
  #   enable = true;
  #   countries = [ "US" ];
  #   autoconnect = null;
  #   address = "10.x.x.x/32"; # from your AirVPN config
  # };
}
