{
  config,
  lib,
  pkgs,
  mkProxyVhost,
  ...
}:

let
  cfg = config.proxy.nextcloud;
  proxyOptions = import ./options.nix;

  # Static HTML with SSI directive — gixy can't see variables in external files.
  # SSI substitutes $nc_share_token (set by nginx location capture) to build the DAV URL.
  discordEmbedPage = pkgs.writeTextDir "embed.html" ''
    <!DOCTYPE html><html><head>
    <meta property="og:type" content="video.other"/>
    <meta property="og:video:url" content="https://${cfg.domain}/public.php/dav/files/<!--# echo var="nc_share_token" -->"/>
    <meta property="og:video:secure_url" content="https://${cfg.domain}/public.php/dav/files/<!--# echo var="nc_share_token" -->"/>
    <meta property="og:video:type" content="video/mp4"/>
    <meta property="og:video:width" content="2560"/>
    <meta property="og:video:height" content="1440"/>
    </head><body></body></html>
  '';
in
{
  options.proxy.nextcloud = lib.mkOption {
    type = lib.types.submodule proxyOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = lib.recursiveUpdate
      (mkProxyVhost {
        inherit cfg;
        proxyPass = "http://nextcloud-nix.lan:80";

        # Specific nextcloud config
        extraExtraConfig = lib.concatStringsSep "\n" [
          "client_max_body_size 10g;"
          "client_body_buffer_size 400M;"
        ];
      })
      {
        # Serve OG video meta tags to Discord bot so share links embed.
        # Points og:video at /public.php/dav/files/TOKEN/ which returns raw video.
        # Normal users get the regular Nextcloud share page.
        locations."~ ^/s/([\\w]+)$" = {
          proxyPass = "http://nextcloud-nix.lan:80";
          extraConfig = ''
            set $nc_share_token $1;
            error_page 418 = @nc_discord_embed;
            if ($http_user_agent ~* "Discordbot") {
              return 418;
            }
          '';
        };
        locations."@nc_discord_embed" = {
          extraConfig = ''
            internal;
            ssi on;
            default_type text/html;
            root ${discordEmbedPage};
            try_files /embed.html =404;
          '';
        };
      };
  };
}
