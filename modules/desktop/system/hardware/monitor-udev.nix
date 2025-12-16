{
  inputs,
  pkgs,
  ...
}:
let
  igpu = pkgs.writeTextFile {
    name = "igpu-udev";
    text = ''KERNEL=="card*", KERNELS=="0000:6d:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/amd-igpu"'';
    destination = "/etc/udev/rules.d/amd-igpu-dev-path.rules"; # The destination path within the generated package
  };
in
{
  services.udev.packages = [ igpu ];
}
