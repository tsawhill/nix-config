{ self, modulesPath, ... }:

let
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "server-nix";
  system.stateVersion = "25.11";
  imports = [
    # Home Manager
    ./home-manager.nix
    # Boot
    ./system/boot.nix
    # NVIDIA gpu
    ./hardware/nvidia.nix
    # Disks
    ./system/disks.nix
    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network
    ./system/networking.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"
    # User and group mapping for containers
    ./system/id-mappings.nix

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/desktop.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/keys/laptop.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles/all.nix"
    "${self}/modules/software/services/incus.nix"

  ];
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
  };
}
