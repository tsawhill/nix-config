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
  streamOutput = "HDMI-A-1";
  boltLauncher = pkgs.bolt-launcher.override { jdk17 = pkgs.openjdk; };

  # Modes absent from the HDMI dummy plug's EDID. Native EDID modes remain
  # available alongside these; refresh rates are expressed in millihertz.
  customStreamModes = [
    # AYN Thor lower display (landscape)
    {
      width = 1240;
      height = 1080;
      refreshMilliHz = 60000;
      blanking = "reduced";
    }
    # Alienware AW3423DWF ultrawide
    {
      width = 3440;
      height = 1440;
      refreshMilliHz = 60000;
      blanking = "reduced";
    }
    {
      width = 3440;
      height = 1440;
      refreshMilliHz = 120000;
      blanking = "reduced";
    }
    {
      width = 3440;
      height = 1440;
      refreshMilliHz = 165000;
      blanking = "reduced";
    }
  ];

  nvidiaClientEnvironment = {
    __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS = "/run/opengl-driver/share/egl/egl_external_platform.d";
    __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
  };

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
  nvidiaGraphicsEnvironment = nvidiaClientEnvironment // {
    GBM_BACKEND = "nvidia-drm";
    KWIN_DRM_DEVICES = "/dev/dri/card1";
    LD_PRELOAD = "${pkgs.libglvnd}/lib/libEGL.so.1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  runRuneLite = pkgs.writeShellScript "sunshine-run-runelite" ''
    # Sunshine needs this preload for capture and encoding, but passing it to
    # Qt/Java clients prevents them from selecting the mounted NVIDIA driver.
    unset LD_PRELOAD GBM_BACKEND KWIN_DRM_DEVICES
    exec ${boltLauncher}/bin/bolt-launcher "$@"
  '';

  waitForKWin = pkgs.writeShellScript "sunshine-wait-for-kwin" ''
    set -eu

    # kwin_wayland_wrapper creates the socket before the compositor is ready.
    # Wait for the compositor's D-Bus name so clients do not connect to a
    # socket that no process is servicing yet.
    for _ in $(seq 1 1800); do
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

    for _ in $(seq 1 600); do
      outputs="$(${pkgs.coreutils}/bin/timeout --kill-after=0.2s 0.5s \
        ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -o 2>/dev/null || true)"
      if printf '%s\n' "$outputs" \
        | ${pkgs.gnugrep}/bin/grep -q '${streamOutput}'; then
        exit 0
      fi
      sleep 0.1
    done

    echo "${streamOutput} did not become ready" >&2
    exit 1
  '';

  ensureCustomStreamModes = pkgs.writeShellScript "sunshine-ensure-custom-stream-modes" ''
    set -eu

    ${waitForKWin}
    ${waitForOutput}

    modes="$(${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -j)"
    ${lib.concatMapStringsSep "\n" (
      mode:
      let
        refreshHz = builtins.div mode.refreshMilliHz 1000;
        modeName = "${toString mode.width}x${toString mode.height}@${toString refreshHz}";
      in
      ''
        if ! printf '%s\n' "$modes" | ${lib.getExe pkgs.jq} -e \
          --arg output ${lib.escapeShellArg streamOutput} \
          --arg mode ${lib.escapeShellArg modeName} \
          '[.outputs[] | select(.name == $output) | .modes[] | select(.name == $mode)] | length > 0' \
          >/dev/null; then
          ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} \
            ${lib.escapeShellArg "output.${streamOutput}.addCustomMode.${toString mode.width}.${toString mode.height}.${toString mode.refreshMilliHz}.${mode.blanking}"}
          modes="$(${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -j)"
        fi
      ''
    ) customStreamModes}
  '';

  setClientStreamMode = pkgs.writeShellScript "sunshine-set-client-stream-mode" ''
    set -eu

    width=''${SUNSHINE_CLIENT_WIDTH:-}
    height=''${SUNSHINE_CLIENT_HEIGHT:-}
    fps=''${SUNSHINE_CLIENT_FPS:-}

    if ! ${lib.getExe pkgs.jq} -en \
      --arg width "$width" --arg height "$height" --arg fps "$fps" \
      '($width | tonumber) > 0 and ($height | tonumber) > 0 and ($fps | tonumber) > 0' \
      >/dev/null 2>&1; then
      echo "Invalid Moonlight display mode: ''${width}x''${height}@''${fps}" >&2
      exit 1
    fi

    mode_id="$(${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -j \
      | ${lib.getExe pkgs.jq} -r \
        --arg output ${lib.escapeShellArg streamOutput} \
        --argjson width "$width" --argjson height "$height" --argjson fps "$fps" '
          first(
            .outputs[]
            | select(.name == $output)
            | .modes[]
            | select(
                .size.width == $width
                and .size.height == $height
                and (.refreshRate - $fps) < 1
                and (.refreshRate - $fps) > -1
              )
            | .id
          ) // empty
        ')"

    if [ -z "$mode_id" ]; then
      echo "Moonlight requested unavailable mode ''${width}x''${height}@''${fps}" >&2
      echo "Available modes:" >&2
      ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -j \
        | ${lib.getExe pkgs.jq} -r \
          --arg output ${lib.escapeShellArg streamOutput} \
          '.outputs[] | select(.name == $output) | .modes[].name' >&2
      exit 1
    fi

    exec ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} \
      "output.${streamOutput}.mode.$mode_id"
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

      # Sunshine's keyboard and two mouse devices live for the lifetime of
      # the daemon, while its touch and pen devices are recreated for every
      # client connection. Restarting KWin for those per-client devices tears
      # down the Wayland session and kills open applications on every resume.
      # Keep native touch/pen unavailable in this LXC so reconnecting only
      # resumes the existing desktop.
      device_name="$(<"/sys/class/input/$event/device/name")"
      case "$device_name" in
        "Keyboard passthrough" | "Mouse passthrough" | "Mouse passthrough (absolute)") ;;
        *) continue ;;
      esac

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

  software.apps.gaming.enable = true;

  # nvidia-runtime.nix bind-mounts the host driver over /run/opengl-driver, so
  # the guest must not build its own. programs/steam.nix still reads package
  # and package32, which graphics.nix only defines when enabled.
  hardware.graphics = {
    enable = lib.mkForce false;
    package = pkgs.mesa;
    package32 = pkgs.pkgsi686Linux.mesa;
  };

  services.sunshine = {
    # KWin capture does not need CAP_SYS_ADMIN. Avoiding the capability wrapper
    # also preserves the EGL loader environment for Sunshine.
    capSysAdmin = lib.mkForce false;

    settings = {
      sunshine_name = "sunshine-nix";
      capture = "kwin";
      output_name = streamOutput;
      csrf_allowed_origins = "https://sunshine-nix.lan:47990,https://10.73.73.140:47990";
      system_tray = "disabled";
      global_prep_cmd = builtins.toJSON [
        {
          do = "${setClientStreamMode}";
          undo = "${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} output.${streamOutput}.mode.1920x1080@120";
          elevated = false;
        }
      ];
    };

    applications.apps = [
      {
        name = "Desktop";
        auto-detach = "true";
      }
      {
        name = "RuneLite";
        cmd = "${runRuneLite}";
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
      "download"
      "games"
      "wheel"
      "video"
      "input"
      "render"
    ];
  };
  users.groups.download.gid = 1001;
  users.groups.games.gid = 1005;

  # No display manager runs here, so nothing supplies the session environment
  # and a lingering systemd --user never sources /etc/profile. Plasma starts
  # plasmashell from its own units, which inherit the manager, not the units
  # above. Kickoff resolves $XDG_MENU_PREFIX + applications.menu, and only
  # plasma-applications.menu exists, so without the prefix the menu is empty.
  systemd.user.extraConfig = ''
    DefaultEnvironment=XDG_DATA_DIRS=/etc/profiles/per-user/${user}/share:/run/current-system/sw/share XDG_MENU_PREFIX=plasma- XDG_CURRENT_DESKTOP=KDE
  '';

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
    serviceConfig.Type = "oneshot";
    script = ''
      target=/mnt/gamesaves/runelite
      parent=/home/${user}/.local/share/bolt-launcher
      link=$parent/.runelite

      ${pkgs.coreutils}/bin/install -d -m 0755 -o ${user} -g users "$parent"
      if [ ! -d "$target" ]; then
        ${pkgs.coreutils}/bin/install -d -m 2775 -o ${user} -g games "$target"
      fi

      # The Incus idmapped gamesaves mount does not support POSIX ACLs. Keep
      # file ownership intact while making the shared games group writable;
      # setgid directories carry that group into newly created entries.
      ${pkgs.coreutils}/bin/chgrp -R games "$target"
      ${pkgs.coreutils}/bin/chmod -R g+rwX "$target"
      ${pkgs.findutils}/bin/find "$target" -type d \
        -exec ${pkgs.coreutils}/bin/chmod g+s {} +

      if [ -L "$link" ]; then
        ${pkgs.coreutils}/bin/ln -sfnT "$target" "$link"
        ${pkgs.coreutils}/bin/chown -h ${user}:users "$link"
      elif [ ! -e "$link" ]; then
        ${pkgs.coreutils}/bin/ln -s "$target" "$link"
        ${pkgs.coreutils}/bin/chown -h ${user}:users "$link"
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

  systemd.user.services.sunshine-display-modes = {
    description = "Add custom Sunshine display modes to KWin";
    wantedBy = [ "default.target" ];
    after = [ "plasma-kwin_wayland.service" ];
    partOf = [ "plasma-kwin_wayland.service" ];
    unitConfig.ConditionUser = user;
    environment = sessionEnvironment;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${ensureCustomStreamModes}";
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

  # Extend Plasma's packaged service instead of replacing it. It must survive
  # the intentional KWin restart used to discover Sunshine's virtual input.
  systemd.user.services.plasma-plasmashell = {
    overrideStrategy = "asDropin";
    after = [ "plasma-kwin_wayland.service" ];
    # NixOS gives a declaratively extended user service a minimal PATH. Since
    # plasmashell launches desktop entries such as `Exec=dolphin %u`, it also
    # needs the full system profile rather than only systemd's helper tools.
    path = [ config.system.path ];
    environment = nvidiaClientEnvironment;
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.RestartSec = "2s";
  };

  # Sunshine connects to the plasma Wayland session
  systemd.user.services.sunshine = {
    wantedBy = lib.mkForce [ "default.target" ];
    unitConfig.ConditionUser = user;
    partOf = lib.mkForce [ ];
    wants = lib.mkForce [
      "plasma-headless.service"
      "sunshine-display-modes.service"
    ];
    after = lib.mkForce [
      "plasma-headless.service"
      "sunshine-display-modes.service"
    ];
    environment =
      sessionEnvironment
      // nvidiaGraphicsEnvironment
      // {
        DISPLAY = ":0";
        # FFmpeg dlopens libcuda.so.1, which ships only in the Incus driver mount
        # and is missing from the guest loader cache, so NVENC probing fails and
        # Sunshine falls back to the Vulkan encoder. This directory carries no
        # GLVND dispatchers, so it cannot shadow the preloaded libglvnd libEGL.
        LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      };
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
