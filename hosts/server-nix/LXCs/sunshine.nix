{
  config,
  lib,
  self,
  pkgs,
  ...
}:

let
  user = "taylor";
  waylandDisplay = "wayland-0";
  boltLauncher = pkgs.bolt-launcher.override { jdk17 = pkgs.openjdk; };

  sessionEnvironment = {
    DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    KDE_FULL_SESSION = "true";
    KDE_SESSION_VERSION = "6";
    QT_QPA_PLATFORM = "wayland";
    WAYLAND_DISPLAY = waylandDisplay;
    XDG_CURRENT_DESKTOP = "KDE";
    XDG_SESSION_DESKTOP = "KDE";
    XDG_SESSION_TYPE = "wayland";
  };

  # Keep the version-independent GLVND dispatcher in the guest while loading
  # the driver-version-specific NVIDIA EGL implementation from server-nix.
  nvidiaGraphicsEnvironment = {
    GBM_BACKEND = "nvidia-drm";
    KWIN_DRM_DEVICES = "/dev/dri/card1";
    LD_PRELOAD = "${pkgs.libglvnd}/lib/libEGL.so.1";
    __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS = "/run/opengl-driver/share/egl/egl_external_platform.d";
    __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  waitForKWin = pkgs.writeShellScript "sunshine-wait-for-kwin" ''
    set -eu

    # kwin_wayland_wrapper creates the socket before the compositor is ready.
    # Wait for the compositor's D-Bus name so clients do not connect to a
    # socket that no process is servicing yet.
    for _ in $(seq 1 300); do
      if ${pkgs.systemd}/bin/busctl --user --no-pager list 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -q '^org\.kde\.KWin '; then
        break
      fi
      sleep 0.1
    done

    if ! ${pkgs.systemd}/bin/busctl --user --no-pager list 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -q '^org\.kde\.KWin '; then
      echo "KWin did not become ready" >&2
      exit 1
    fi
  '';

  waitForOutput = pkgs.writeShellScript "sunshine-wait-for-output" ''
    set -eu

    for _ in $(seq 1 60); do
      outputs="$(${pkgs.coreutils}/bin/timeout --kill-after=0.2s 0.5s \
        ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -o 2>/dev/null || true)"
      if printf '%s\n' "$outputs" \
        | ${pkgs.gnugrep}/bin/grep -q 'HDMI-A-1'; then
        exit 0
      fi
      sleep 0.1
    done

    echo "HDMI-A-1 did not become ready" >&2
    exit 1
  '';

  # Incus hotplugs Sunshine's uinput event nodes, but an unprivileged LXC
  # cannot synthesize the corresponding udev events. Mirror the host's udev
  # records so libinput can classify the passed keyboard and mouse.
  syncInputMetadata = pkgs.writeShellScript "sunshine-sync-input-metadata" ''
    set -eu
    shopt -s nullglob

    ${pkgs.coreutils}/bin/install -d -m 0755 /run/udev/data
    changed=0

    for device in /dev/input/event*; do
      event="''${device##*/}"
      id_path="/sys/class/input/$event/device/id"
      [ -r "$id_path/vendor" ] || continue
      [ -r "$id_path/product" ] || continue
      [ "$(<"$id_path/vendor")" = beef ] || continue
      [ "$(<"$id_path/product")" = dead ] || continue

      device_number="$(${pkgs.coreutils}/bin/stat -c '%t:%T' "$device")"
      major_hex="''${device_number%%:*}"
      minor_hex="''${device_number##*:}"
      record="c$((16#$major_hex)):$((16#$minor_hex))"
      source="/opt/host-udev-data/$record"
      target="/run/udev/data/$record"

      [ -r "$source" ] || continue
      if [ "$(${pkgs.coreutils}/bin/readlink "$target" 2>/dev/null || true)" != "$source" ]; then
        ${pkgs.coreutils}/bin/ln -sfnT "$source" "$target"
        changed=1
      fi
    done

    if [ "$changed" -eq 1 ]; then
      # KWin's DRM backend discovers input through libinput at startup. The
      # restart occurs only when a new udev record is linked. Keep Sunshine
      # running so its uinput devices remain present while KWin restarts.
      ${pkgs.systemd}/bin/systemctl --user --machine=${user}@ \
        try-restart plasma-kwin_wayland.service
    fi
  '';
in
{
  imports = [
    ./base
    ./nvidia-runtime.nix
    "${self}/modules/software/services/sunshine.nix"
  ];

  networking.hostName = "sunshine-nix";
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = false;

  services.sunshine = {
    # KWin capture does not need CAP_SYS_ADMIN. Avoiding the capability wrapper
    # also preserves the EGL loader environment for Sunshine.
    capSysAdmin = lib.mkForce false;

    settings = {
      sunshine_name = "sunshine-nix";
      capture = "kwin";
      output_name = "HDMI-A-1";
      csrf_allowed_origins = "https://sunshine-nix.lan:47990,https://10.73.73.140:47990";
      system_tray = "disabled";
    };

    applications.apps = [
      {
        name = "Desktop";
        auto-detach = "true";
      }
      {
        name = "RuneLite";
        cmd = "${boltLauncher}/bin/bolt-launcher";
        auto-detach = "true";
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    boltLauncher
    kdePackages.libkscreen
    kdePackages.qtwayland
    xorg.xcbutilcursor
  ];

  boot.kernelModules = [ "uinput" ];

  users.users.taylor = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "input"
      "render"
    ];
  };

  # Without linger, user services never start on this headless container.
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/${user} 0644 root root -"
    "z /dev/uinput 0660 root input -"
  ];

  systemd.paths.sunshine-input-metadata = {
    description = "Watch for Sunshine input devices";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/dev/input";
      Unit = "sunshine-input-metadata.service";
    };
  };

  systemd.services.sunshine-input-metadata = {
    description = "Expose Sunshine input udev metadata to libinput";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Coalesce the keyboard and both mouse hotplug events.
      ${pkgs.coreutils}/bin/sleep 1
      ${syncInputMetadata}
    '';
  };

  # Keep the mutable RuneLite profile on the shared gamesaves dataset. Never
  # replace a real directory: that could hide data created before this mount
  # and link were configured.
  systemd.services.sunshine-runelite-data = {
    description = "Link RuneLite data to the gamesaves dataset";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathIsMountPoint = "/mnt/gamesaves";
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = "users";
    };
    script = ''
      target=/mnt/gamesaves/runelite
      parent=/home/${user}/.local/share/bolt-launcher
      link=$parent/.runelite

      ${pkgs.coreutils}/bin/install -d -m 0755 "$target" "$parent"

      if [ -L "$link" ]; then
        ${pkgs.coreutils}/bin/ln -sfnT "$target" "$link"
      elif [ ! -e "$link" ]; then
        ${pkgs.coreutils}/bin/ln -s "$target" "$link"
      else
        echo "Not replacing existing non-symlink RuneLite data at $link" >&2
      fi
    '';
  };

  systemd.user.services.plasma-headless = {
    description = "Headless KDE Plasma Wayland Session";
    wantedBy = [ "default.target" ];
    after = [ "dbus.socket" ];
    unitConfig.ConditionUser = user;

    path = with pkgs; [
      kdePackages.kwin
      kdePackages.plasma-workspace
      xwayland
    ];

    environment = sessionEnvironment;

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # The virtual backend does not initialize libinput, so Sunshine's synthetic
  # keyboard and mouse are invisible to Plasma. Use the passed NVIDIA DRM
  # device and its connected HDMI output instead.
  systemd.user.services.plasma-kwin_wayland = {
    # The wrapper starts kwin_wayland and Xwayland by name. This unit otherwise
    # receives only systemd's basic PATH and silently remains as a socket-owning
    # wrapper with no compositor behind it.
    path = [
      pkgs.kdePackages.kwin
      pkgs.xwayland
    ];
    environment =
      sessionEnvironment
      // nvidiaGraphicsEnvironment
      // {
        # This is a dedicated, single-user streaming LXC. Without the override,
        # a cold KWin start hides its screencast protocol from systemd-launched
        # Sunshine because there is no desktop-file security context.
        KWIN_WAYLAND_NO_PERMISSION_CHECKS = "1";
      };

    serviceConfig.ExecStart = lib.mkForce (
      "${lib.getExe' pkgs.kdePackages.kwin "kwin_wayland_wrapper"} " + "--xwayland --drm --no-lockscreen"
    );
  };

  # Sunshine connects to the plasma Wayland session
  systemd.user.services.sunshine = {
    wantedBy = lib.mkForce [ "default.target" ];
    unitConfig.ConditionUser = user;
    partOf = lib.mkForce [ ];
    wants = lib.mkForce [ "plasma-headless.service" ];
    after = lib.mkForce [ "plasma-headless.service" ];
    environment = sessionEnvironment // nvidiaGraphicsEnvironment // { DISPLAY = ":0"; };
    serviceConfig = {
      ExecStartPre = [
        "${waitForKWin}"
        "${waitForOutput}"
      ];
      Restart = lib.mkForce "always";
    };
  };

  warnings = lib.optional (lib.versionOlder pkgs.sunshine.version "2026.516.143833") ''
    sunshine-nix is configured for KDE/Wayland capture = "kwin", but the selected Sunshine package is ${pkgs.sunshine.version}.
    Use Sunshine >= 2026.516.143833 for KWin capture support.
  '';
}
