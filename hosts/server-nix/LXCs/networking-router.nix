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

  my.network.router = {
    enable = true;
    # Flip with the OPNsense VM stopped. Rollback: stop this container, start OPNsense.
    takeover = false;
  };
}
