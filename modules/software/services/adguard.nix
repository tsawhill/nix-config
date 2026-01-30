{
  networking.firewall.allowedTCPPorts = [
    53
    80
    3000
  ];
  networking.firewall.allowedUDPPorts = [
    53
    80
    3000
  ];
  services.adguardhome = {
    enable = true;
    allowDHCP = false;
    port = 80;
  };
}
