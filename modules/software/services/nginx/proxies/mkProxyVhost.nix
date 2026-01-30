{ lib, ... }:
{
  _module.args.mkProxyVhost =
    {
      proxyPass,
      proxyWebsockets ? false,
      cfg,
      extraExtraConfig ? "",
    }:
    {
      # Pull the domain from the cfg object passed in
      # This is used as the 'key' in the virtualHosts attribute set
      # but since this function returns the 'value' part,
      # we just define the configuration here.

      forceSSL = true;
      sslCertificate = "/Certs/fullchain.pem";
      sslCertificateKey = "/Certs/key.pem";
      # This forces Nginx to only listen on IPv4 + port 443
      listen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
      ];

      locations."/" = {
        inherit proxyPass;
        inherit proxyWebsockets;
      };

      extraConfig = lib.concatStringsSep "\n" [
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
