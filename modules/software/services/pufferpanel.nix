{ pkgs, ... }:
{
  services.pufferpanel = {
    enable = true;
    extraPackages = [ pkgs.javaPackages.compiler.openjdk21 ];
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
