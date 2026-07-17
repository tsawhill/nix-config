{ ... }:
{
  # 512GB NVMe (nvme0n1): 1G ESP, ~467G ext4 root, ~8.8G swap.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/82b57b47-9845-49f5-90fb-386d752d8aca";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0D20-3211";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/bee63fd0-1998-4ec8-bd1d-fcbd092e0162"; }
  ];
}
