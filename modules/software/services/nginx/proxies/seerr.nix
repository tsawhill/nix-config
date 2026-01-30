{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.seerr;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.seerr = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://jellyseerr-nix.lan:5055";
    };
  };
}
