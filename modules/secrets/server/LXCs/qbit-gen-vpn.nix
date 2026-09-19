{ config, lib, ... }:
{
  options.my.secrets.qbit-gen-vpn.enable = lib.mkEnableOption "the private qbit-gen AirVPN port";
  config = lib.mkIf config.my.secrets.qbit-gen-vpn.enable {
    sops.secrets.qbit_gen_vpn_port = {
      sopsFile = ./qbit-gen-vpn.yaml;
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
