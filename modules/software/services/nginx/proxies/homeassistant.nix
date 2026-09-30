{
  config,
  lib,
  mkProxyVhost,
  networkTopology,
  ...
}:

let
  cfg = config.proxy.homeassistant;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.homeassistant = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://${networkTopology.lib.fqdn "homeassistant-nix"}:8123";
      # The frontend talks to HA over a websocket.
      proxyWebsockets = true;
    };
  };
}
