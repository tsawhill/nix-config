{
  config,
  lib,
  pkgs,
  ...
}:

let
  acmeCfg = config.my.nginx.acme;
  geoblockCfg = config.my.nginx.geoblock;
in
{
  options.my.nginx = {
    acme = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Issue and renew the shared wildcard certificate locally on this nginx host.";
      };

      certificateName = lib.mkOption {
        type = lib.types.str;
        default = "tsawhill";
        description = "Name of the local ACME certificate under /var/lib/acme.";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = "tsawhill.org";
        description = "Primary domain for the local ACME certificate.";
      };

      extraDomainNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "*.tsawhill.org" ];
        description = "Additional domain names for the local ACME certificate.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "me@tsawhill.org";
        description = "Email address used for ACME account registration.";
      };
    };

    geoblock = {
      enable = lib.mkEnableOption "country-based blocking for nginx proxy virtual hosts";

      allowedCountryCodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "US" ];
        description = "ISO country codes allowed through nginx proxy virtual hosts.";
      };

      allowPrivateNetworks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow RFC1918, loopback, link-local, and ULA clients even when no country is known.";
      };

      database = lib.mkOption {
        type = lib.types.path;
        default = "${pkgs.dbip-country-lite}/share/dbip/dbip-country-lite.mmdb";
        description = "MaxMind-compatible country database used by ngx_http_geoip2_module.";
      };

      blockStatus = lib.mkOption {
        type = lib.types.int;
        default = 444;
        description = "HTTP status returned for blocked countries. Nginx status 444 closes the connection.";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.nginx = {
        enable = true;
        logError = "/var/log/nginx/error.log warn";
        recommendedTlsSettings = true;
        recommendedProxySettings = true;
      };
      networking.firewall.allowedTCPPorts = [ 443 ];
    }

    (lib.mkIf acmeCfg.enable {
      my.secrets.acme_env.enable = true;

      security.acme = {
        acceptTerms = true;
        defaults = {
          email = acmeCfg.email;
          dnsResolver = "9.9.9.9:53";
        };
        certs.${acmeCfg.certificateName} = {
          domain = acmeCfg.domain;
          inherit (acmeCfg) extraDomainNames;
          dnsProvider = "cloudflare";
          environmentFile = config.sops.secrets.acme_env.path;
          group = "nginx";
          reloadServices = [ "nginx.service" ];
        };
      };

      systemd.services.nginx = {
        wants = [ "acme-${acmeCfg.certificateName}.service" ];
        after = [ "acme-${acmeCfg.certificateName}.service" ];
      };
    })

    (lib.mkIf geoblockCfg.enable {
      services.nginx = {
        additionalModules = [ pkgs.nginxModules.geoip2 ];

        commonHttpConfig = ''
          geoip2 ${geoblockCfg.database} {
            $geoip2_country_code country iso_code;
          }

          geo $nginx_geoblock_private_network {
            default 0;
            127.0.0.0/8 1;
            10.0.0.0/8 1;
            172.16.0.0/12 1;
            192.168.0.0/16 1;
            100.64.0.0/10 1;
            ::1/128 1;
            fc00::/7 1;
            fe80::/10 1;
          }

          map $geoip2_country_code $nginx_geoblock_allowed_country {
            default 0;
            ${lib.concatMapStringsSep "\n" (country: "${country} 1;") geoblockCfg.allowedCountryCodes}
          }

          map "$nginx_geoblock_allowed_country:$nginx_geoblock_private_network" $nginx_geoblock_deny {
            default 1;
            "1:0" 0;
            "1:1" 0;
            ${lib.optionalString geoblockCfg.allowPrivateNetworks ''"0:1" 0;''}
          }
        '';
      };
    })
  ];
}
