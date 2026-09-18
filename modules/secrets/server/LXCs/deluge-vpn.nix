{ config, lib, ... }:
{
  options.my.secrets.deluge-vpn.enable = lib.mkEnableOption "the private Deluge AirVPN port";
  config = lib.mkIf config.my.secrets.deluge-vpn.enable {
    sops.secrets.deluge_vpn_port = {
      sopsFile = ./deluge-vpn.yaml;
      key = "forwarded_port";
      mode = "0400";
      restartUnits = lib.optionals (config.systemd.services.deluged.enable or false) [
        "deluged.service"
      ];
      reloadUnits = lib.optionals config.networking.firewall.enable [ "firewall.service" ];
    };
  };
}
