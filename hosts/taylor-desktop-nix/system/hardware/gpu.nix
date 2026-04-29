{ pkgs, ... }:
let
  # Udev rules to create stable symlinks for igpu/dgpu by vendor:device ID.
  # PCI bus addresses shift when cards are added/removed, so match on hardware IDs
  # instead. Confirm with: lspci -nn | grep VGA
  #   dGPU: 1002:744c (Navi 31 — RX 7900 XTX)
  #   iGPU: 1002:164e (Raphael — 7900X integrated)
  igpu = pkgs.writeTextFile {
    name = "igpu-udev";
    text = ''KERNEL=="card*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x164e", SYMLINK+="dri/amd-igpu"'';
    destination = "/etc/udev/rules.d/amd-igpu-dev-path.rules";
  };
  # gpu-screen-recorder scans from card0; if cards don't start at 0 it fails.
  # Symlink card0 to the iGPU (which has the monitors attached).
  card0 = pkgs.writeTextFile {
    name = "card0-udev";
    text = ''KERNEL=="card*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x164e", SYMLINK+="dri/card0"'';
    destination = "/etc/udev/rules.d/amd-card0-dev-path.rules";
  };
  dgpu = pkgs.writeTextFile {
    name = "dgpu-udev";
    text = ''KERNEL=="card*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x744c", SYMLINK+="dri/amd-dgpu"'';
    destination = "/etc/udev/rules.d/amd-dgpu-dev-path.rules";
  };
in
{
  services.udev.packages = [ igpu dgpu card0 ];

  # ROCm OpenCL runtime — required for GPU compute in DaVinci Resolve
  hardware.graphics.extraPackages = [ pkgs.rocmPackages.clr ];
}
