{
  config,
  lib,
  ...
}:

let
  # Leave false for the factory run. After the factory adds this host's age
  # recipient: add it to the cloudflare/ddns.yaml and wireguard/endpoint.yaml
  # rules, run `sops updatekeys` on both, then flip this.
  ddnsEnabled = true;
  placeholder = config.sops.placeholder;
in
{
  imports = [ ./base ];

  networking.hostName = "networking-ddns-nix";

  my.secrets.cloudflare.ddns.enable = ddnsEnabled;
  my.secrets.wireguard.endpoint.enable = ddnsEnabled;

  # Same Cloudflare setup as pi-backup's, but the record name is a secret, so the
  # whole config is a sops template instead of ddclient's generated one.
  sops.templates."ddclient.conf" = lib.mkIf ddnsEnabled {
    content = ''
      cache=/var/lib/ddclient/ddclient.cache
      foreground=YES
      usev4=webv4, webv4=ipify-ipv4
      login=token
      password=${placeholder.cloudflare_ddns_api_token}
      protocol=cloudflare
      zone=tsawhill.org
      ssl=yes
      ttl=1
      quiet=no
      verbose=no
      ${placeholder.wg_remote_endpoint}
    '';
    restartUnits = [ "ddclient.service" ];
  };

  services.ddclient = lib.mkIf ddnsEnabled {
    enable = true;
    interval = "5min";
    configFile = config.sops.templates."ddclient.conf".path;
  };
}
