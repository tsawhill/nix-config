{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.lidarr;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.lidarr = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://arrs-nix.lan:8686";
    };
  };
}
