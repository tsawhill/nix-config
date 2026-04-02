{
  self,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  buildSSHUsers = [ "root" ];
  laptopSSHUsers = [ "taylor" ];
  phoneSSHUsers = [ "taylor" ];

  # Use the latest ZFS-compatible kernel
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${pkgs.zfs_unstable.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  networking.hostName = "taylor-desktop-nix";
  system.stateVersion = "25.11";

  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-unstable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix

    # Hardware
    ./hardware-configuration.nix
    ./system/boot.nix
    ./system/disks.nix
    ./system/hardware.nix
    ./system/lact.nix
    ./system/networking.nix
    ./system/syncthing.nix
    ./system/samba.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/laptop.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"

    # Desktop
    "${self}/modules/software/desktop"

    # Hardware services
    "${self}/modules/software/services/openrgb.nix"
  ];

  boot.kernelPackages = latestKernelPackage;
  boot.zfs.package = pkgs.zfs_unstable;

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  desktop.hyprland.enable = true;
  services.upower.enable = true;

  software.dev.enable = true;
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.media.enable = true;
  software.apps.gaming.enable = true;
  software.apps.emulators.enable = true;
  software.apps.printing.enable = true;
  software.apps.tools.enable = true;

  my.secrets.syncthing.desktop-nix.enable = true;

  my.users.taylor = {
    enable = true;
    extraGroups = [
      "i2c"
      "input"
      "video"
    ];
    sudoer = true;
  };
}
