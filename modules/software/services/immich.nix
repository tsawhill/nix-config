{ config, pkgs, ... }:
{
  # TEMP: 2.x is EOL on 26.05; drop when moving to 26.11 (Immich 3.x).
  nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];

  services.immich = {
    enable = true;
    accelerationDevices = null;
    mediaLocation = "/mnt/zpool/immich";
    host = "0.0.0.0";
  };

  networking.firewall.allowedTCPPorts = [
    2283
  ];
  networking.firewall.allowedUDPPorts = [
    2283
  ];
  users.users.immich.extraGroups = [
    "media"
  ];
  users.users.redis-immich.extraGroups = [
    "media"
  ];
}
