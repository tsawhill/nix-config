{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.unifi;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.unifi = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "https://${networkTopology.lib.fqdn "unifi-nix"}:8443";
    };
  };
}
