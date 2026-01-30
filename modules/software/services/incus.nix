{ pkgs, ... }:
{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
  };
  networking = {
    nftables.enable = true;
    firewall.allowedTCPPorts = [
      8443
    ];
  };
  users.users.taylor.extraGroups = [ "incus-admin" ];
}
