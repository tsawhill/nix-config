{ config, lib, ... }:
{
  options.my.secrets.qbit-lts-vpn.enable = lib.mkEnableOption "the private qbit-lts AirVPN port";
  config = lib.mkIf config.my.secrets.qbit-lts-vpn.enable {
    sops.secrets.qbit_lts_vpn_port = {
      sopsFile = ./qbit-lts-vpn.yaml;
      key = "forwarded_port";
      mode = "0400";
      # Also evaluated on the VPN gateway, which has no qBittorrent unit.
      restartUnits = lib.optionals (config.services.qbittorrent.enable or false) [
        "qbittorrent.service"
      ];
      reloadUnits = lib.optionals config.networking.firewall.enable [ "firewall.service" ];
    };
  };
}
