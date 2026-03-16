{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.immich;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.immich = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://immich-nix.lan:2283";
      proxyWebsockets = true;

      # Specific immich config
      extraExtraConfig = lib.concatStringsSep "\n" [
        "client_max_body_size 50000M;"
        "proxy_read_timeout   600s;"
        "proxy_send_timeout   600s;"
        "send_timeout         600s;"
      ];
    };
  };
}
