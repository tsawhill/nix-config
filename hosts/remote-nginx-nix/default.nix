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
in
{
  networking.hostName = "remote-nginx-nix";
  system.stateVersion = "26.05";
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
    "${self}/modules/nix/cachix.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"

    # Nginx
    "${self}/modules/software/services/nginx/nginx.nix"
    "${self}/modules/software/services/nginx/streams/palworld.nix"

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
}
