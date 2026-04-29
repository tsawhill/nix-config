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
  # gpu-screen-recorder scans /dev/dri/card0 first and stops if it doesn't exist.
  # When cards enumerate starting at card1, create a real device node at card0
  # (not a symlink — gsr skips those) pointing to the iGPU.
  card0 = pkgs.writeTextFile {
    name = "card0-udev";
    text = ''KERNEL=="card*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x164e", RUN+="${pkgs.coreutils}/bin/cp -a /dev/dri/%k /dev/dri/card0"'';
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
