{
  self,
  ...
}:

{
  imports = [
    ./base
    "${self}/modules/network/dhcp.nix"
  ];

  networking.hostName = "networking-dhcp-nix";

  # OPNsense's LAN DHCP must stay off; two servers on one broadcast domain race.
  my.networking.dhcp.enable = true;
}
