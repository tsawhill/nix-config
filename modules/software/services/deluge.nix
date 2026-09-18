{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.deluge;
  privatePort = cfg.portSecret != null;
  portFile = config.sops.secrets.${cfg.portSecret}.path;
in
{
  options.my.services.deluge.portSecret = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "SOPS secret used at runtime for Deluge's listening port and firewall.";
  };
  config = {
    assertions = [
      {
        assertion = !privatePort || !config.networking.nftables.enable;
        message = "Deluge private-port firewall rules require the iptables firewall backend.";
      }
    ];
    systemd.services.deluged = {
      enable = true;
      path = [ pkgs.deluged ];
      after = lib.optionals privatePort [ "sops-install-secrets.service" ];
      requires = lib.optionals (privatePort && config.sops.useSystemdActivation) [
        "sops-install-secrets.service"
      ];
      preStart = lib.optionalString privatePort ''
        ${pkgs.python3}/bin/python3 ${../../../pkgs/vpn-egress/deluge_port.py} \
          /root/.config/deluge/core.conf ${lib.escapeShellArg portFile}
      '';

      unitConfig = {
        Description = "Deluge Bittorrent Client Daemon";
        Documentation = "man:deluged";
        After = "network-online.target";
      };

      serviceConfig = {
        Type = "simple";
        UMask = "007";
        ExecStart = "${pkgs.deluged}/bin/deluged -d";
        Restart = "on-failure";
        TimeoutStopSec = "300";
        User = "root";
        Group = "root";
        SupplementaryGroups = "download";
      };

      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.deluge-web = {
      enable = true;

      unitConfig = {
        Description = "Deluge Bittorrent Client Web UI";
        Documentation = "man:deluge-web";
        After = "deluged.service";
        Wants = "deluged.service";
      };

      serviceConfig = {
        Type = "simple";
        UMask = "027";
        ExecStart = "${pkgs.deluged}/bin/deluge-web -d";
        Restart = "on-failure";
        User = "root";
        Group = "root";
        SupplementaryGroups = "download";
      };

      wantedBy = [ "multi-user.target" ];
    };
    networking.firewall.allowedTCPPorts = [
      8112
      58846
    ];
    networking.firewall.allowedUDPPorts = [
      58846
    ];
    networking.firewall.extraCommands = lib.optionalString privatePort ''
      port=$(cat ${lib.escapeShellArg portFile})
      if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
        echo "Invalid Deluge forwarded-port secret" >&2
        exit 1
      fi
      iptables -A nixos-fw -p tcp --dport "$port" -j nixos-fw-accept
      iptables -A nixos-fw -p udp --dport "$port" -j nixos-fw-accept
    '';
    systemd.services.firewall = lib.mkIf privatePort {
      after = [ "sops-install-secrets.service" ];
      requires = lib.optionals config.sops.useSystemdActivation [ "sops-install-secrets.service" ];
    };
  };
}
