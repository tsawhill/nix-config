{
  services._3proxy = {
    enable = true;
    services = [
      {
        type = "socks";
        auth = [ "strong" ];
        acl = [
          {
            rule = "allow";
            users = [ "taylor" ];
          }
        ];
      }
    ];
    usersFile = "/etc/3proxy.passwd";
  };

  networking.firewall.allowedTCPPorts = [ 1080 ];
  networking.firewall.allowedUDPPorts = [ 1080 ];
}
