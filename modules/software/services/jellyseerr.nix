{
  networking.firewall.allowedTCPPorts = [ 5055 ];
  services.jellyseerr = {
    enable = true;
  };
}
