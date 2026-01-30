{
  services.nginx.streamConfig = ''
    server {
        proxy_pass 10.73.73.69:27017;
        listen 27017;
      }
  '';
}
