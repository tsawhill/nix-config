{ pkgs, ... }:
let
  # Udev rules to create stable symlinks for igpu/dgpu by PCI address
  igpu = pkgs.writeTextFile {
    name = "igpu-udev";
    text = ''KERNEL=="card*", KERNELS=="0000:6f:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/amd-igpu"'';
    destination = "/etc/udev/rules.d/amd-igpu-dev-path.rules";
  };
  dgpu = pkgs.writeTextFile {
    name = "dgpu-udev";
    text = ''KERNEL=="card*", KERNELS=="0000:03:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/amd-dgpu"'';
    destination = "/etc/udev/rules.d/amd-dgpu-dev-path.rules";
  };
in
{
  services.udev.packages = [ igpu dgpu ];

  # ROCm OpenCL runtime — required for GPU compute in DaVinci Resolve
  hardware.graphics.extraPackages = [ pkgs.rocmPackages.clr ];
}
