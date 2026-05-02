{
  self,
  lib,
  modulesPath,
  inputs,
  ...
}:

let
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  serverSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "pi-backup-nix";
  system.stateVersion = "25.11";
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    ./system/disks.nix
    ./system/networking.nix
    ./system/zfs-backup-target.nix
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
    (import "${self}/modules/ssh/pubkeys/desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/server-nix-root.nix" serverSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    # "${self}/modules/software/bundles/all.nix"
    "${self}/modules/software/packages/zsh.nix"
    # "${self}/modules/software/services/incus.nix"

  ];
  # NixOS defaults include x86-only modules (e.g. i8042) that don't exist
  # in the Pi's ARM kernel, causing the initrd build to fail.
  boot.initrd.includeDefaultModules = false;

  # Use the new nixos-raspberrypi kernel bootloader; disable extlinux
  # which gets pulled in by the aarch64 sd-image module.
  boot.loader.raspberry-pi.bootloader = "kernel";
  boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

  # Bypass the Pi 5 boot-time PSU safety check. The Pi warns and halts
  # at a red screen if it detects a <5A USB-PD supply, even when the
  # board is actually powered via GPIO (e.g. from a SATA HAT). This
  # makes headless/remote reboots work without pressing the power button.
  hardware.raspberry-pi.config.all.options.usb_max_current_enable = {
    enable = true;
    value = 1;
  };

  # Enable the external PCIe x1 slot (off by default on Pi 5). Required
  # for the Radxa Penta SATA HAT (JMB585) to appear in lspci.
  hardware.raspberry-pi.config.all.base-dt-params = {
    pciex1 = {
      enable = true;
    };
    # Gen3 is unofficial but the JMB585 handles it reliably and doubles
    # throughput vs the default Gen2.
    pciex1_gen = {
      enable = true;
      value = 3;
    };
  };

  my.secrets.wireguard.pi-backup-nix.enable = true;

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
