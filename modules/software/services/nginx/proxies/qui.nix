{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.qui;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.qui = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://${networkTopology.lib.fqdn "qui-nix"}:7476";
      # qui's torrent view streams live updates.
      proxyWebsockets = true;
    };
  };
}
