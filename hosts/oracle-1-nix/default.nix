{
  self,
  inputs,
  pkgs,
  ...
}:

/*
  oracle-1-nix — public reverse proxy on an OCI VM.Standard.A1.Flex
  (aarch64, 1 OCPU / 6 GB). Replaces remote-nginx-nix and the hand-built
  oracle-rocky-proxy.

  First install goes through ./bootstrap.nix, not this file.
*/
let
  desktopSSHUsers = [ "root" ];
  laptopSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "root" ];
in
{
  networking.hostName = "oracle-1-nix";
  system.stateVersion = "26.05";

  imports = [
    # Disk layout (disko owns the partition table)
    inputs.disko.nixosModules.disko

    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    # Hardware / boot / disks
    ./system/hardware.nix
    ./system/boot.nix
    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network (pulls in networking-base.nix + wg-remote)
    ./system/networking.nix
    "${self}/modules/network/networkmanager/wireguard/wg-remote.nix"
    # Firewall
    ./system/firewall.nix
    # Users
    "${self}/modules/users"

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/cachix.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software. Only the core CLI bundle: the full modules/software/bundles
    # tree also pulls in the gui-apps option set, which this headless aarch64
    # box has no use for.
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
