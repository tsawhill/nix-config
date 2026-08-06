{
  networking.firewall.allowedTCPPorts = [ 5055 ];
  services.seerr = {
    enable = true;
  };
}
