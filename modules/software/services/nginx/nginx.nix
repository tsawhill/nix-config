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
