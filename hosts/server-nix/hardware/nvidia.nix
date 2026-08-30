{ config, ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # The active GPU LXCs consume this exact host package through the Incus
    # runtime export, so normal nixpkgs updates can safely advance the driver.
    # 595 leaves Xwayland's glamor GLX with no fbconfigs, so X11 clients such
    # as RuneLite get no OpenGL at all. Hold on the 580 branch until a later
    # driver reaches nixpkgs-stable.
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    open = true;
  };
}
