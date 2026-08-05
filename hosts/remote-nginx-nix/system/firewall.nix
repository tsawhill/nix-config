{
  networking.firewall = {
    enable = true;
    interfaces."remotewg" = {
      allowedTCPPorts = [
        22
        443
        80
        25565
        8211
      ];
      allowedUDPPorts = [
        27017
        8211
      ];
    };
    interfaces."ens3" = {
      allowedTCPPorts = [
        443
        25565
        8211
      ];
      allowedUDPPorts = [
        27017
        8211
      ];
    };
  };
}
