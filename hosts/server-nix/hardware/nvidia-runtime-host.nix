{
  config,
  lib,
  pkgs,
  ...
}:

let
  driver = config.hardware.nvidia.package;
  graphicsPackages =
    [ config.hardware.graphics.package ]
    ++ config.hardware.graphics.extraPackages
    ++ (with pkgs; [
      libdrm
      libffi
      libgbm
      stdenv.cc.cc.lib
      wayland
    ]);
  graphicsRuntime = pkgs.buildEnv {
    name = "nvidia-lxc-graphics-runtime-${driver.version}";
    paths = map lib.getLib graphicsPackages;
    ignoreCollisions = true;
  };

  # Incus cannot use the Nix store references embedded in the host driver from
  # a container with its own store. Copy the complete host graphics environment
  # behind the normal NixOS driver path and rewrite its lookup paths to that
  # stable location. The external EGL platform libraries are required by
  # graphical consumers such as KWin even though CUDA-only consumers do not use
  # them.
  nvidiaRuntime =
    pkgs.runCommand "nvidia-lxc-runtime-${driver.version}"
      {
        nativeBuildInputs = [ pkgs.patchelf ];
      }
      ''
        mkdir -p "$out/bin" "$out/lib"

        cp -aL ${graphicsRuntime}/. "$out/"
        # Nix store files are read-only, but the copied ELF and metadata need
        # to be patched below. The merged graphics environment already includes
        # the NVIDIA etc/share payload, so do not copy it over itself again.
        chmod -R u+w "$out"
        install -m 0755 ${driver.bin}/bin/nvidia-smi "$out/bin/nvidia-smi"

        while IFS= read -r elf; do
          if patchelf --print-rpath "$elf" >/dev/null 2>&1; then
            patchelf --set-rpath /run/opengl-driver/lib "$elf"
          fi
        done < <(find "$out/lib" -type f)

        patchelf \
          --set-interpreter /run/opengl-driver/lib/ld-linux-x86-64.so.2 \
          --set-rpath /run/opengl-driver/lib \
          "$out/bin/nvidia-smi"

        # Supply the loader and libc used by the host-built NVIDIA binaries. This
        # keeps the runtime independent of both the guest's glibc and Nix store.
        cp -a ${pkgs.glibc}/lib/. "$out/lib/"

        # GLVND, EGL, and Vulkan manifests use absolute package paths. All
        # libraries have been flattened above, so point those manifests at the
        # stable guest path as well.
        while IFS= read -r metadata; do
          sed -Ei \
            's#/nix/store/[a-z0-9]{32}-[^" ]+/lib/#/run/opengl-driver/lib/#g' \
            "$metadata"
        done < <(grep -rl /nix/store "$out/etc" "$out/share")

        echo ${driver.version} > "$out/driver-version"
      '';
in
{
  # Give Incus a stable, non-symlink source path. Existing containers retain
  # their current bind after an upgrade until they are explicitly restarted.
  systemd.mounts = [
    {
      description = "Host NVIDIA userspace runtime for Incus containers";
      before = [ "incus.service" ];
      wantedBy = [ "local-fs.target" ];
      what = toString nvidiaRuntime;
      where = "/run/host-nvidia-runtime";
      type = "none";
      options = "bind,ro";
    }
  ];

  # The declarative profile update must not race the new source mount during a
  # live server switch.
  systemd.services.incus-declarative-apply.unitConfig.RequiresMountsFor = [
    "/run/host-nvidia-runtime"
  ];
}
