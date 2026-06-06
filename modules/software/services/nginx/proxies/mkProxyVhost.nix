{
  config,
  lib,
  networkTopology,
  ...
}:
{
  _module.args.mkProxyVhost =
    {
      proxyPass,
      proxyWebsockets ? false,
      cfg,
      extraExtraConfig ? "",
      # Allow passing a different outpost URL, but default to main one
      authentikOutpost ? "http://${networkTopology.lib.fqdn "authentik-nix"}:9000",
    }:
    let
      # --- Define Authentik Configuration Blocks Locally ---

      # The configuration injected into the main "/" location
      authentikRootConfig = ''
        auth_request /outpost.goauthentik.io/auth/nginx;
        error_page 401 = @goauthentik_proxy_signin;
        auth_request_set $auth_cookie $upstream_http_set_cookie;
        add_header Set-Cookie $auth_cookie;
        auth_request_set $authentik_username $upstream_http_x_authentik_username;
        proxy_set_header X-authentik-username $authentik_username;
      '';

      # The extra locations required for the outpost to work
      authentikLocations = {
        "/outpost.goauthentik.io" = {
          extraConfig = ''
            proxy_pass ${authentikOutpost}/outpost.goauthentik.io;
            proxy_set_header Host $host;
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
            add_header Set-Cookie $auth_cookie;
            auth_request_set $auth_cookie $upstream_http_set_cookie;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
          '';
        };
        "/outpost.goauthentik.io/auth/nginx" = {
          extraConfig = ''
            proxy_pass ${authentikOutpost}/outpost.goauthentik.io/auth/nginx;
            proxy_set_header Host $host;
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
            add_header Set-Cookie $auth_cookie;
            auth_request_set $auth_cookie $upstream_http_set_cookie;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
          '';
        };
        "@goauthentik_proxy_signin" = {
          extraConfig = ''
            internal;
            add_header Set-Cookie $auth_cookie;
            return 302 /outpost.goauthentik.io/start?rd=$request_uri;
          '';
        };
      };
    in
    {
      forceSSL = true;
      sslCertificate =
        if config.my.nginx.acme.enable then
          "/var/lib/acme/${config.my.nginx.acme.certificateName}/fullchain.pem"
        else
          "/Certs/fullchain.pem";
      sslCertificateKey =
        if config.my.nginx.acme.enable then
          "/var/lib/acme/${config.my.nginx.acme.certificateName}/key.pem"
        else
          "/Certs/key.pem";
      listen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
      ];

      # Logic:
      # 1. Start with the standard root location.
      # 2. If enableAuthentik is true, append the extraRootConfig.
      # 3. If enableAuthentik is true, merge the authentikLocations set.
      locations = {
        "/" = {
          inherit proxyPass proxyWebsockets;
          # Conditionally add the auth_request lines
          extraConfig = lib.optionalString cfg.enableAuthentik authentikRootConfig;
        };
      }
      // (if cfg.enableAuthentik then authentikLocations else { });

      extraConfig = lib.concatStringsSep "\n" [
        (lib.optionalString config.my.nginx.geoblock.enable ''
          if ($nginx_geoblock_deny) {
            return ${toString config.my.nginx.geoblock.blockStatus};
          }
        '')

        (lib.optionalString (cfg.mTLSCert != null) ''
          ssl_client_certificate /etc/mTLSCerts/${cfg.mTLSCert}.crt;
          ssl_verify_client on;
        '')

        (lib.optionalString (cfg.restrictToIPs != [ ]) ''
          ${lib.concatMapStrings (ip: "allow ${ip};\n") cfg.restrictToIPs}
          deny all;
        '')

        extraExtraConfig
      ];
    };
}
