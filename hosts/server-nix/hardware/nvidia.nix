{ config, ... }:

let
  # The host and GPU LXCs must use the exact same NVIDIA userspace version
  # because the containers share the host's kernel module. Update this pin only
  # as a coordinated host + GPU-LXC driver upgrade.
  pinnedDriver = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    version = "580.173.02";
    sha256_64bit = "sha256-jY65AB4FqaimY9PV0wT+tk7yhE7hhczf2VJ4aCD0bhs=";
    sha256_aarch64 = "sha256-1lvVYIfvTXjwSoCNp4g8NaWQHF/TfpXRUKdgLrqXqoA=";
    openSha256 = "sha256-lhloZdf6XbaAFTZBF1DxE0Nv9VC6obY8UPf0VyfVepE=";
    settingsSha256 = "sha256-dfdu/3tnwHUfP7WoeQFNOMalMlpmUWjeMDIOnu+yi8E=";
    persistencedSha256 = "sha256-j8YM1w231X+JIP3c3TpUNurEBumEu1stVjzFGWu1JXE=";
  };
in
{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = pinnedDriver;
    open = true;
  };
}
