{ config, ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # The active GPU LXCs consume this exact host package through the Incus
    # runtime export, so normal nixpkgs updates can safely advance the driver.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;
  };
}
