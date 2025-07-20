{
  pkgs,
  lib,
  config,
  ...
}:
let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{

  imports = [
    ./hardware-configuration.nix
    ./system
    ./user_definition
  ];
  system.stateVersion = "24.11";

  boot.kernelPackages = latestKernelPackage;

 
  services.desktopManager.gnome.enable = true;
 boot.zfs.package = pkgs.zfs_unstable;
}
