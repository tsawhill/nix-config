{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.open-webui;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.open-webui = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://llm-nix.lan:8080";
      proxyWebsockets = true;
    };
  };
}
