{
  self,
  modulesPath,
  inputs,
  ...
}:

let
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "pi-backup-nix";
  system.stateVersion = "25.11";
  imports = [

    # Home Manager
    ./home-manager.nix
    # Locale
    "${self}/modules/locale/enUS-pacific.nix"

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/desktop.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/keys/laptop.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Software
    # "${self}/modules/software/bundles/all.nix"
    "${self}/modules/software/packages/zsh.nix"
    # "${self}/modules/software/services/incus.nix"

  ];
  raspberry-pi-nix.board = "bcm2712"; # BCM2712 is the Pi 5 SoC

  my.users.taylor = {
    enable = true;
    sudoer = true;
  };
  my.groups = {
    media = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1003;
    };
    documents = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1004;
    };
  };
}
