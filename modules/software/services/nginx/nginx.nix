{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.nginx.geoblock;
in
{
  options.my.nginx.geoblock = {
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

  config = lib.mkMerge [
    {
      services.nginx = {
        enable = true;
        logError = "/var/log/nginx/error.log warn";
        recommendedTlsSettings = true;
        recommendedProxySettings = true;
      };
      systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/Certs/" ];
      networking.firewall.allowedTCPPorts = [ 443 ];
    }

    (lib.mkIf cfg.enable {
      services.nginx = {
        additionalModules = [ pkgs.nginxModules.geoip2 ];

        commonHttpConfig = ''
          geoip2 ${cfg.database} {
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
            ${lib.concatMapStringsSep "\n" (country: "${country} 1;") cfg.allowedCountryCodes}
          }

          map "$nginx_geoblock_allowed_country:$nginx_geoblock_private_network" $nginx_geoblock_deny {
            default 1;
            "1:0" 0;
            "1:1" 0;
            ${lib.optionalString cfg.allowPrivateNetworks ''"0:1" 0;''}
          }
        '';
      };
    })
  ];
}
