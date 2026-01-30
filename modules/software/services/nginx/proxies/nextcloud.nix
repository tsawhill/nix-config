{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.nextcloud;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.nextcloud = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://nextcloud-nix.lan:80";

      # Specific nextcloud config
      extraExtraConfig = lib.concatStringsSep "\n" [
        "client_max_body_size 10g;"
        "client_body_buffer_size 400M;"
      ];
    };
  };
}
