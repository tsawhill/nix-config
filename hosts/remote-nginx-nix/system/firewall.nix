{
  networking.firewall = {
    enable = true;
    interfaces."remotewg" = {
      allowedTCPPorts = [
        22
        443
        80
        25565
      ];
      allowedUDPPorts = [ 27017 ];
    };
    interfaces."ens3" = {
      allowedTCPPorts = [
        443
        80
        25565
      ];
      allowedUDPPorts = [ 27017 ];
    };
  };
}
