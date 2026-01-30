{ config, pkgs, ... }:
{

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
