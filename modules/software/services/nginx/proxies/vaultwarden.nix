{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.vaultwarden;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.vaultwarden = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://${networkTopology.lib.fqdn "vaultwarden-nix"}:8000";
    };
  };
}
