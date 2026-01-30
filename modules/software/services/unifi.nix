{ pkgs, ... }:
{
  services.unifi = {
    enable = true;
    openFirewall = true;
    mongodbPackage = pkgs.mongodb-ce;
  };
  networking.firewall.allowedTCPPorts = [ 8443 ];
  networking.firewall.allowedUDPPorts = [ 8443 ];
}
