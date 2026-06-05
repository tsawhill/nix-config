{ ... }:
{
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # WireGuard tunnel back to the home network. allowedIPs cover the LAN and the
  # remote WG subnet so LAN services resolve when the deck is off-site.
  my.secrets.wireguard.pubkeys.enable = true;
  my.network.wg-remote = {
    enable = true;
    address = "10.50.50.4/32";
    autoconnect = "true";
    dns = "10.73.73.6";
    dnsPriority = 50;
    routeMetric = 50000;
    peer = {
      endpoint = "taylordnsfree.zapto.org:51820";
      allowedIPs = "10.50.50.0/24;10.73.73.0/24;";
    };
  };

  # AirVPN (disabled). To enable:
  #   1. Generate a WireGuard config for this device in the AirVPN client area.
  #   2. Create modules/secrets/wireguard/taylor-deck-nix/wg-airvpn.yaml with
  #      private_key + preshared_key (see sops templates in the setup notes).
  #   3. Enable the secret in hosts/taylor-deck-nix/default.nix
  #      (my.secrets.wireguard.taylor-deck-nix.wg-airvpn.enable = true).
  #   4. Set `address` to the AirVPN-assigned tunnel IP and pick a server below.
  # my.network.airvpn = {
  #   enable = true;
  #   countries = [ "US" ];
  #   autoconnect = null;
  #   address = "10.x.x.x/32"; # from your AirVPN config
  # };
}
