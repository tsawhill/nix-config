{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.authentik;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.authentik = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://authentik-nix.lan:9000";
      proxyWebsockets = true;
      extraExtraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };
}
