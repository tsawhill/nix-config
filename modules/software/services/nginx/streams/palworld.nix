{ networkTopology, ... }:
{
  services.nginx.streamConfig = ''
    server {
        proxy_pass ${networkTopology.lib.fqdn "palworld-nix"}:8211;
        listen 8211 udp;
      }
  '';
}
