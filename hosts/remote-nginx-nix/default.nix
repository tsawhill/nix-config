{
  self,
  inputs,
  modulesPath,
  pkgs,
  ...
}:

let
  desktopSSHUsers = [ "root" ];
  laptopSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "root" ];
  acmeSSHUsers = [
    "nginx"
    "root"
  ];
in
{
  networking.hostName = "remote-nginx-nix";
  system.stateVersion = "25.11";
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

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
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)
    (import "${self}/modules/ssh/pubkeys/acme-nix-root.nix" acmeSSHUsers)

    # Software
    "${self}/modules/software/bundles"

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
  users.users.nginx = {
    # This tells NixOS not to use the 'nologin' shell
    shell = pkgs.zsh;
  };

  proxy.authentik = {
    enable = true;
    domain = "auth.tsawhill.org";
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
    domain = "nc.tsawhill.org";
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
    # mTLSCert = "mTLS-CA";
    enableAuthentik = true;
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
  };
  proxy.unifi = {
    enable = true;
    domain = "unifi.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.searx = {
    enable = true;
    domain = "searx.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
}
