{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.dnsRecovery;
  settings = pkgs.writeText "dns-recovery.json" (
    builtins.toJSON {
      inherit (cfg) service port upstreams;
      kdig = "${pkgs.knot-dns}/bin/kdig";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      stateFile = "/var/lib/dns-recovery/state.json";
    }
  );
in
{
  options.my.services.dnsRecovery = {
    enable = lib.mkEnableOption "upstream-gated DNS service recovery";
    service = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption { type = lib.types.port; };
    upstreams = lib.mkOption {
      type = lib.types.listOf (lib.types.listOf lib.types.str);
      description = "kdig arguments for upstream checks, using literal addresses to avoid a DNS dependency.";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.dns-recovery = {
      description = "Recover local DNS only when its upstream can resolve";
      after = [
        "network-online.target"
        "${cfg.service}.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "dns-recovery";
        ExecStart = "${pkgs.python3}/bin/python3 ${../../../pkgs/vpn-egress/dns_recovery.py} ${settings}";
        TimeoutStartSec = "90s";
      };
    };
    systemd.timers.dns-recovery = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitInactiveSec = "30s";
      };
    };
  };
}
