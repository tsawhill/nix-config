{
  config,
  lib,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.sonarr;
  proxyOptions = import ./options.nix;
in
{
  options.proxy.sonarr = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = mkProxyVhost {
      inherit cfg;
      proxyPass = "http://arrs-nix.lan:8989";
      extraExtraConfig = ''
        # 1. Clear any conflicting headers from the bouncer
        auth_request_set $auth_header $upstream_http_authorization;

        # 2. Force the connection to stay alive for the header handoff
        proxy_set_header Authorization $auth_header;

        # 3. CRITICAL: If $auth_header is empty (which happens on mobile), 
        # fall back to the original browser header
        if ($auth_header = "") {
          set $auth_header $http_authorization;
        }

        proxy_set_header Authorization $auth_header;
        proxy_pass_header Authorization;
      '';
    };
  };
}
