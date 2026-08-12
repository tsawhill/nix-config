{ pkgs, ... }:

{
  # /run/opengl-driver is supplied by Incus, so the guest must not replace it
  # with its own NixOS graphics-driver environment.
  hardware.graphics.enable = false;

  # Incus mounts devices before the guest creates its /run tmpfs, so mounting
  # there directly would be hidden during boot. Keep the Incus payload under
  # /opt and establish the standard NixOS driver path from inside the guest.
  systemd.mounts = [
    {
      description = "Host NVIDIA userspace runtime";
      wantedBy = [ "local-fs.target" ];
      before = [ "jellyfin.service" ];
      what = "/opt/host-nvidia-runtime";
      where = "/run/opengl-driver";
      type = "none";
      options = "bind,ro";
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
