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
  dgpu = pkgs.writeTextFile {
    name = "dgpu-udev";
    text = ''KERNEL=="card*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x744c", SYMLINK+="dri/amd-dgpu"'';
    destination = "/etc/udev/rules.d/amd-dgpu-dev-path.rules";
  };
in
{
  services.udev.packages = [ igpu dgpu ];

  # ROCm OpenCL runtime — required for GPU compute in DaVinci Resolve
  hardware.graphics.extraPackages = [ pkgs.rocmPackages.clr.icd ];

  # RDNA 3 (gfx1100) — explicit version so ROCm/DaVinci Resolve detect GPU
  environment.variables.HSA_OVERRIDE_GFX_VERSION = "11.0.0";
}
