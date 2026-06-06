{ networkTopology, ... }:
{
  services.nginx.streamConfig = ''
    server {
        proxy_pass ${networkTopology.lib.fqdn "pufferpanel-nix"}:25565;
        listen 25565;
      }
  '';
}
