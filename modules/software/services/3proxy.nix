{ config, ... }:
{
  my.secrets.socks5_passwd.enable = true;

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
    usersFile = "/run/credentials/3proxy.service/passwd";
  };

  # DynamicUser can't read the root-owned sops file directly.
  systemd.services."3proxy".serviceConfig.LoadCredential =
    "passwd:${config.sops.secrets.socks5_passwd.path}";

  networking.firewall.allowedTCPPorts = [ 1080 ];
  networking.firewall.allowedUDPPorts = [ 1080 ];
}
