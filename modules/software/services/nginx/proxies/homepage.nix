{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.homepage;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.homepage = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://${networkTopology.lib.fqdn "homepage-nix"}:8080";
    };
  };
}
