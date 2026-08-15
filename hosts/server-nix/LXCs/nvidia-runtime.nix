{ pkgs, ... }:

{
  # /run/opengl-driver is supplied by Incus, so the guest must not replace it
  # with its own NixOS graphics-driver environment.
  hardware.graphics.enable = false;

  # Incus mounts devices before the guest creates its /run tmpfs, so mounting
  # there directly would be hidden during boot. Keep the Incus payload under
  # /opt and establish the standard NixOS driver path from inside the guest.
  # A live switch from hardware.graphics can leave its /run/opengl-driver
  # symlink behind; systemd refuses to use a symlink as a mount point.
  systemd.services.prepare-host-nvidia-runtime = {
    description = "Prepare the host NVIDIA runtime mount point";
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -L /run/opengl-driver ]; then
        ${pkgs.coreutils}/bin/rm /run/opengl-driver
      fi
      ${pkgs.coreutils}/bin/mkdir -p /run/opengl-driver
    '';
  };

  systemd.mounts = [
    {
      description = "Host NVIDIA userspace runtime";
      requires = [ "prepare-host-nvidia-runtime.service" ];
      after = [ "prepare-host-nvidia-runtime.service" ];
      wantedBy = [ "local-fs.target" ];
      what = "/opt/host-nvidia-runtime";
      where = "/run/opengl-driver";
      type = "none";
      options = "bind,ro";
      mountConfig.LazyUnmount = true;
    }
  ];

  # The actual utility and driver libraries come from server-nix through the
  # nvidia-gpu Incus profile. This keeps the command conventional for users and
  # monitoring without installing a second NVIDIA userspace driver in the LXC.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nvidia-smi" ''
      exec /run/opengl-driver/bin/nvidia-smi "$@"
    '')
  ];
}
