{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:

let
  cfg = config.my.network.router.portShaping;
  inherit (networkTopology.lib) lanIp;

  shaperConfig = pkgs.writeText "port-shaper.json" (
    builtins.toJSON {
      switch = cfg.switchAddress;
      interfaces = [ "eth0" ] ++ lib.attrNames networkTopology.zones;
      ifb = "lanshape";
      inherit (cfg) headroom;
      macTtlSeconds = cfg.macTtlHours * 3600;
    }
  );
  shaper = pkgs.writeShellScriptBin "port-shaper" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.iproute2
        pkgs.net-snmp
      ]
    }:$PATH
    exec ${pkgs.python3}/bin/python3 ${../../pkgs/port-shaper/controller.py} --config ${shaperConfig} "$@"
  '';
  # The SNMP credential only exists inside a unit, so dry runs go through systemd too.
  shaperPlan = pkgs.writeShellScriptBin "port-shaper-plan" ''
    exec ${config.systemd.package}/bin/systemd-run --pipe --quiet --collect \
      -p LoadCredential=snmp.conf:${cfg.snmpConfigFile} \
      -p StateDirectory=port-shaper \
      ${shaper}/bin/port-shaper plan
  '';
in
{
  options.my.network.router.portShaping = {
    enable = lib.mkEnableOption ''
      shaping LAN egress toward switch ports slower than the router's uplink, so the
      switch's small buffers don't drop bursts on the 10G to 1G step-down.
      Ports, speeds and which MACs sit behind them come from the switch over SNMP
    '';

    switchAddress = lib.mkOption {
      type = lib.types.str;
      default = lanIp "netgear-switch";
      description = "Switch to read the forwarding table and port speeds from.";
    };

    snmpConfigFile = lib.mkOption {
      type = lib.types.str;
      description = "net-snmp snmp.conf with the SNMPv3 credentials (defVersion, defSecurityName, ...).";
    };

    headroom = lib.mkOption {
      type = lib.types.float;
      default = 0.95;
      description = "Fraction of each port's link speed to shape to.";
    };

    macTtlHours = lib.mkOption {
      type = lib.types.ints.positive;
      default = 24;
      description = "How long a MAC stays shaped after it ages out of the switch's table.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1m";
      description = "How often to re-read the switch.";
    };
  };

  config = lib.mkIf (config.my.network.router.enable && cfg.enable) {
    systemd.services.port-shaper = {
      description = "Shape LAN egress to slow switch ports at their link speed";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${shaper}/bin/port-shaper sync";
        LoadCredential = "snmp.conf:${cfg.snmpConfigFile}";
        StateDirectory = "port-shaper";
      };
    };

    systemd.timers.port-shaper = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = cfg.interval;
        Unit = "port-shaper.service";
      };
    };

    environment.systemPackages = [
      shaper
      shaperPlan
    ];
  };
}
