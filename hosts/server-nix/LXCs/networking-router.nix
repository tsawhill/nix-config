{
  self,
  ...
}:

{
  imports = [
    ./base
    "${self}/modules/network/router.nix"
  ];

  networking.hostName = "networking-router-nix";

  # Upstream is OPNsense on the legacy LAN until the WAN moves here.
  my.network.router.enable = true;
}
