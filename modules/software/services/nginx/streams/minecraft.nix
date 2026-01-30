{
  services.nginx.streamConfig = ''
    server {
        proxy_pass pufferpanel-nix.lan:25565;
        listen 25565;
      }
  '';
}
