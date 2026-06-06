{ networkTopology, ... }:
{
  services.nginx.streamConfig = ''
    server {
        proxy_pass ${networkTopology.lib.lanIp "taylor-desktop-nix"}:27017;
        listen 27017;
      }
  '';
}
