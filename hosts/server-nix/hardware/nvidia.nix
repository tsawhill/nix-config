{ config, pkgs, ... }:

{
  # CUDA in the GPU guests needs /dev/nvidia-uvm, which the driver only creates on
  # first host-side CUDA use. Incus passes through the nodes that exist when a guest
  # starts, so without this every guest started after a reboot had no CUDA.
  boot.kernelModules = [ "nvidia_uvm" ];
  systemd.services.nvidia-uvm-devices = {
    description = "Create NVIDIA UVM device nodes for the GPU guests";
    wantedBy = [
      "multi-user.target"
      "incus.service"
    ];
    before = [ "incus.service" ];
    after = [ "systemd-modules-load.service" ];
    path = [
      pkgs.coreutils
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      major=$(awk '$2 == "nvidia-uvm" { print $1 }' /proc/devices)
      if [ -z "$major" ]; then
        echo "nvidia_uvm is not loaded" >&2
        exit 1
      fi
      [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$major" 0
      [ -e /dev/nvidia-uvm-tools ] || mknod -m 666 /dev/nvidia-uvm-tools c "$major" 1
    '';
  };

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

    # Without this nvidia_drm never loads, so the GPU exposes no DRM device and
    # Incus has no /dev/dri to hand the GPU guests. It had been loaded by hand
    # and survived only because this host went so long between reboots.
    modesetting.enable = true;
  };
}
