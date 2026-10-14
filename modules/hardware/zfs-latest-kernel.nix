{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.boot.zfsLatestKernel;

  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    builtins.match "linux_[0-9]+_[0-9]+" name != null
    && (
      let
        zfsCheck = builtins.tryEval (
          kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken
        );
      in
      zfsCheck.success && !zfsCheck.value
    )
  ) pkgs.linuxKernel.packages;
  sortedKernelPackages = lib.sort (a: b: lib.versionOlder a.kernel.version b.kernel.version) (
    builtins.attrValues zfsCompatibleKernelPackages
  );
in
{
  options.my.boot.zfsLatestKernel.enable =
    lib.mkEnableOption "the newest versioned kernel supported by the configured ZFS package";

  config = lib.mkIf cfg.enable {
    boot.kernelPackages =
      if sortedKernelPackages == [ ] then
        throw "No ZFS-compatible kernel found for ${config.networking.hostName}"
      else
        lib.last sortedKernelPackages;
  };
}
