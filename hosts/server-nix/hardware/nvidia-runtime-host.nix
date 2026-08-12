{ config, pkgs, ... }:

let
  driver = config.hardware.nvidia.package;

  # Incus cannot use the Nix store references embedded in the host driver from
  # a container with its own store. Copy the runtime payload behind the normal
  # NixOS driver path and rewrite its ELF lookup paths to that stable location.
  nvidiaRuntime =
    pkgs.runCommand "nvidia-lxc-runtime-${driver.version}"
      {
        nativeBuildInputs = [ pkgs.patchelf ];
      }
      ''
        mkdir -p "$out/bin" "$out/lib"

        cp -a ${driver}/lib/. "$out/lib/"
        cp -a ${driver}/etc "$out/"
        cp -a ${driver}/share "$out/"
        cp -a ${driver.bin}/bin/nvidia-smi "$out/bin/"
        chmod -R u+w "$out"

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

        while IFS= read -r metadata; do
          substituteInPlace "$metadata" \
            --replace-fail ${driver} /run/opengl-driver
        done < <(grep -rl ${driver} "$out/etc" "$out/share")

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
