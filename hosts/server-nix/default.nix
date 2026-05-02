{
  self,
  config,
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
  networking.hostName = "server-nix";
  system.stateVersion = "25.11";
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    # Boot
    ./system/boot.nix
    # NVIDIA gpu
    ./hardware/nvidia.nix
    # Disks and alerts
    ./system/disks.nix
    ./system/zfs-backups.nix
    "${self}/modules/monitoring"

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network
    ./system/networking.nix
    ./system/incus
    # CPU frequency scaling and hardware power settings
    ./system/hardware.nix

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
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"
    "${self}/modules/software/services/incus.nix"
    "${self}/modules/software/services/incus-declarative.nix"
    "${self}/modules/software/packages/nixos-factory.nix"
    "${self}/modules/software/packages/incus-sync.nix"

  ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  my.secrets = {
    gotify_token_zfs.enable = true;
    smtp_password_server.enable = true;
    sshclientkey.server-nix-syncoid.enable = true;
    sshclientkey.server-nix-factory.enable = true;
  };
  my.monitoring = {
    notifications = {
      recipientEmail = "me@tsawhill.org";
      smtp = {
        host = "smtp.purelymail.com";
        port = 587;
        user = "server@tsawhill.org";
        from = "server@tsawhill.org";
        passwordFile = config.sops.secrets.smtp_password_server.path;
      };
      gotify = {
        url = "https://gotify.tsawhill.org/message";
        tokenFile = config.sops.secrets.gotify_token_zfs.path;
      };
    };

    zfsAlerts = {
      enable = true;
      gotifyPriority = 5;
    };

    smartAlerts = {
      enable = true;
      gotifyPriority = 8;
    };

    zfsMaintenance = {
      enable = true;
      scrub.interval = "monthly";
      trim.interval = "monthly";
    };
  };
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
    games = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1005;
    };
  };
}
