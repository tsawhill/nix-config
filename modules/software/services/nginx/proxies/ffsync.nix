{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.ffsync;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.ffsync = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  # No mTLS or Authentik here: the Firefox sync client can do neither.
  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://${networkTopology.lib.fqdn "ffsync-nix"}:5000";
    };
  };
}
