{
  config,
  lib,
  ...
}:

let
  cfg = config.my.network.vpnEgress.client;
in
{
  options.my.network.vpnEgress.client = {
    enable = lib.mkEnableOption "leak-proof routing through a dedicated VPN egress gateway";
    gatewayAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    normalGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.73.73.1";
    };
    bypassCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.gatewayAddress != null;
        message = "VPN egress clients require gatewayAddress.";
      }
    ];

    boot.kernel.sysctl = {
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
    };

    systemd.network.networks."50-eth0" = {
      networkConfig.IPv6AcceptRA = lib.mkForce false;
      dhcpV4Config.UseRoutes = false;
      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = cfg.gatewayAddress;
          Metric = 10;
        }
      ]
      ++ map (cidr: {
        Destination = cidr;
        Gateway = cfg.normalGateway;
        Metric = 5;
      }) cfg.bypassCidrs;
    };
  };
}
