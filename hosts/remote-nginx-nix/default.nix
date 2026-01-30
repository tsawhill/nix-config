{ self, modulesPath, ... }:

let
  desktopSSHUsers = [ "root" ];
  laptopSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "root" ];
in
{
  networking.hostName = "remote-nginx-nix";
  system.stateVersion = "25.11";
  imports = [
    # Home Manager
    ./home-manager.nix
    # Boot
    ./system/boot.nix
    # Disks
    ./system/disks.nix
    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network
    ./system/networking.nix
    # Firewall
    ./system/firewall.nix
    # Users
    "${self}/modules/users"

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/desktop.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/keys/laptop.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles/all.nix"

    # Nginx
    "${self}/modules/software/services/nginx/nginx.nix"
    "${self}/modules/software/services/nginx/proxies"
    "${self}/modules/software/services/nginx/streams/minecraft.nix"

    # fail2ban
    "${self}/modules/software/services/fail2ban"
  ];
  my.users.root = {
    enable = true;
  };

  proxy.vaultwarden = {
    enable = true;
    domain = "vault.tsawhill.org";
  };
  proxy.immich = {
    enable = true;
    domain = "immich.tsawhill.org";
  };
  proxy.jellyfin = {
    enable = true;
    domain = "jelly.tsawhill.org";
  };
  proxy.nextcloud = {
    enable = true;
    domain = "nextc.tsawhill.org";
  };
  proxy.open-webui = {
    enable = true;
    domain = "llm.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.gotify = {
    enable = true;
    domain = "gotify.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.radarr = {
    enable = true;
    domain = "rad.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.sonarr = {
    enable = true;
    domain = "son.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.lidarr = {
    enable = true;
    domain = "lid.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.prowlarr = {
    enable = true;
    domain = "pro.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.seerr = {
    enable = true;
    domain = "request.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.unifi = {
    enable = true;
    domain = "unifi.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
}
