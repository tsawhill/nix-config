{
  config,
  lib,
  self,
  pkgs,
  networkTopology,
  ...
}:

let
  user = "taylor";
  uid = 1000;
  # Only one stream compositor runs at a time, so it always gets this socket.
  waylandDisplay = "wayland-0";
  streamOutput = "HEADLESS-1";
  # Matches the desktops' home-manager pointer cursor.
  cursorTheme = "ComixCursors-Opaque-Orange";
  cursorSize = 24;
  boltLauncher = pkgs.bolt-launcher.override { jdk17 = pkgs.openjdk; };
  sunshinePackage = (pkgs.sunshine.override { cudaSupport = true; }).overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./patches/sunshine-probe-after-prep.patch
      ./patches/sunshine-wlr-before-compositor.patch
    ];

    # Upstream's cudaSupport wrapper uses --set, dropping the driver mount the unit needs.
    postFixup = ''
      wrapProgram $out/bin/sunshine \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.vulkan-loader ]}
    '';
  });

  nvidiaClientEnvironment = {
    __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS = "/run/opengl-driver/share/egl/egl_external_platform.d";
    __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
  };

  # Keep the version-independent GLVND dispatcher in the guest while loading
  # the driver-version-specific NVIDIA EGL implementation from server-nix.
  nvidiaGraphicsEnvironment = nvidiaClientEnvironment // {
    GBM_BACKEND = "nvidia-drm";
    GBM_BACKENDS_PATH = "/run/opengl-driver/lib/gbm";
    LD_PRELOAD = "${pkgs.libglvnd}/lib/libEGL.so.1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # The Incus driver mount carries libGLX_nvidia and libGLX_mesa but not the
  # X11 and xcb libraries they link against, so no GLX vendor can load at all.
  glxClientLibraries = lib.makeLibraryPath (
    with pkgs;
    [
      expat
      libdrm
      xorg.libX11
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXxf86vm
      xorg.libxcb
      xorg.libxshmfence
    ]
  );

  # A display-less output on the GPU's render node; input comes only from
  # Sunshine's devices, which libinput sees once their udev records exist.
  compositorEnvironment = nvidiaClientEnvironment // {
    DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    # Xwayland's libgbm ships no backends of its own.
    GBM_BACKENDS_PATH = "/run/opengl-driver/lib/gbm";
    LABWC_UPDATE_ACTIVATION_ENV = "1";
    LIBSEAT_BACKEND = "noop";
    QT_QPA_PLATFORM = "wayland;xcb";
    WLR_BACKENDS = "headless,libinput";
    WLR_HEADLESS_OUTPUTS = "1";
    WLR_LIBINPUT_NO_DEVICES = "1";
    XCURSOR_PATH = "/run/current-system/sw/share/icons";
    XCURSOR_SIZE = toString cursorSize;
    XCURSOR_THEME = cursorTheme;
    XDG_CURRENT_DESKTOP = "labwc:wlroots";
    XDG_SESSION_TYPE = "wayland";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  waybarConfig = pkgs.writeText "waybar.json" (
    builtins.toJSON {
      layer = "top";
      position = "bottom";
      modules-left = [
        "custom/apps"
        "wlr/taskbar"
      ];
      modules-right = [
        "tray"
        "clock"
      ];
      "custom/apps" = {
        format = "Apps";
        on-click = "fuzzel";
        tooltip = false;
      };
      "wlr/taskbar" = {
        on-click = "activate";
        on-click-middle = "close";
      };
      clock.format = "{:%a %d %b  %H:%M}";
    }
  );

  waybarStyle = pkgs.writeText "waybar.css" ''
    * { font-family: sans-serif; font-size: 14px; }
    window#waybar { background: #1e1e2e; color: #cdd6f4; }
    #taskbar button { padding: 0 6px; color: #cdd6f4; }
    #taskbar button.active { background: #45475a; }
    #custom-apps, #tray, #clock { padding: 0 10px; }
  '';

  desktopConfig = pkgs.linkFarm "labwc-stream-desktop" {
    "rc.xml" = pkgs.writeText "rc.xml" ''
      <?xml version="1.0"?>
      <labwc_config>
        <keyboard>
          <default />
          <keybind key="A-f"><action name="ToggleFullscreen" /></keybind>
          <keybind key="W-Return"><action name="Execute" command="foot" /></keybind>
          <keybind key="W-space"><action name="Execute" command="fuzzel" /></keybind>
        </keyboard>
      </labwc_config>
    '';
    "menu.xml" = pkgs.writeText "menu.xml" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <openbox_menu>
        <menu id="root-menu" label="">
          <item label="Applications"><action name="Execute" command="fuzzel" /></item>
          <item label="Terminal"><action name="Execute" command="foot" /></item>
          <item label="Firefox"><action name="Execute" command="firefox" /></item>
          <item label="Steam"><action name="Execute" command="steam" /></item>
          <item label="RuneLite"><action name="Execute" command="bolt-launcher" /></item>
        </menu>
      </openbox_menu>
    '';
    "autostart" = pkgs.writeText "autostart" ''
      ${lib.getExe pkgs.waybar} -c ${waybarConfig} -s ${waybarStyle} >/dev/null 2>&1 &
    '';
  };

  # Games get the whole output: every normal window maximized, undecorated.
  kioskConfig = pkgs.linkFarm "labwc-stream-kiosk" {
    "rc.xml" = pkgs.writeText "rc.xml" ''
      <?xml version="1.0"?>
      <labwc_config>
        <keyboard>
          <default />
          <keybind key="A-f"><action name="ToggleFullscreen" /></keybind>
        </keyboard>
        <windowRules>
          <windowRule identifier="*" type="normal" serverDecoration="no" />
          <windowRule identifier="*" type="normal">
            <action name="Maximize" />
          </windowRule>
        </windowRules>
      </labwc_config>
    '';
  };

  labwc = "${pkgs.labwc}/bin/labwc";

  # Launchers such as Bolt exit once the game is up, and Chromium-based ones
  # move into their own systemd scope, so a game session lasts while the
  # launcher runs or any window is open, ending after 5s without one.
  streamApp = pkgs.writeShellScript "stream-app" ''
    "$@" &
    launcher=$!

    idle=0
    while [ "$idle" -lt 5 ]; do
      if kill -0 "$launcher" 2>/dev/null \
        || [ -n "$(${pkgs.coreutils}/bin/timeout 2 ${lib.getExe pkgs.lswt} -c i 2>/dev/null)" ]; then
        idle=0
      else
        idle=$((idle + 1))
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';

  # One compositor per Moonlight app. Game sessions exit with their game.
  streamSessions = {
    desktop = "${labwc} -C ${desktopConfig}";
    runelite = "${labwc} -C ${kioskConfig} -S '${streamApp} ${lib.getExe' boltLauncher "bolt-launcher"}'";
  };
  streamUnits = lib.concatMapStringsSep " " (name: "stream-${name}.service") (
    lib.attrNames streamSessions
  );

  # Sunshine prep/app commands: start a session at the client's resolution,
  # stop it, or block until it exits so Sunshine ends the stream with it.
  streamSession = pkgs.writeShellScript "stream-session" ''
    set -eu
    shopt -s nullglob
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
        pkgs.util-linux
        pkgs.wlr-randr
      ]
    }

    # Sunshine swallows a prep command's stderr, so log failures to the journal.
    fail() {
      logger -t stream-session -p user.err -- "$*"
      echo "$*" >&2
      exit 1
    }

    userctl() {
      systemctl --user "$@"
    }

    # libinput only picks up devices whose udev records exist when it starts.
    wait_for_input_records() {
      for _ in $(seq 1 50); do
        missing=0
        for node in /dev/input/event*; do
          sys=/sys/class/input/''${node##*/}
          [ ${sunshineInputId} = beef:dead ] || continue
          [ -e "/run/udev/data/c$(cat "$sys/dev" 2>/dev/null)" ] || missing=1
        done
        [ "$missing" -eq 0 ] && return
        sleep 0.1
      done
      logger -t stream-session -p user.warning -- "Starting without every Sunshine input device"
    }

    case "''${1:-}" in
      start)
        session="''${2:?session name required}"
        unit="stream-$session.service"
        width=''${SUNSHINE_CLIENT_WIDTH:-}
        height=''${SUNSHINE_CLIENT_HEIGHT:-}
        fps=''${SUNSHINE_CLIENT_FPS:-}
        number='^[1-9][0-9]*$'
        if ! [[ $width =~ $number && $height =~ $number && $fps =~ $number ]]; then
          fail "Invalid Moonlight display mode: ''${width}x''${height}@''${fps}"
        fi

        wait_for_input_records
        # Free the socket before the new compositor claims it.
        userctl stop ${streamUnits}
        userctl start "$unit"

        for _ in $(seq 1 100); do
          userctl is-active --quiet "$unit" || fail "$unit exited during startup"
          if timeout 1 wlr-randr 2>/dev/null | grep -q '^${streamOutput} '; then
            break
          fi
          sleep 0.1
        done

        timeout 5 wlr-randr --output ${streamOutput} --custom-mode "''${width}x''${height}@''${fps}Hz" \
          || fail "Could not set ${streamOutput} to ''${width}x''${height}@''${fps}"
        ;;
      stop)
        userctl stop ${streamUnits}
        ;;
      wait)
        while userctl is-active --quiet "stream-''${2:?session name required}.service"; do
          sleep 1
        done
        ;;
      *)
        fail "usage: stream-session start <session> | stop | wait <session>"
        ;;
    esac
  '';

  sunshineInputId = ''"$(cat "$sys/device/id/vendor" 2>/dev/null):$(cat "$sys/device/id/product" 2>/dev/null)"'';

  # Incus hotplugs Sunshine's uinput event nodes, but an unprivileged LXC
  # cannot synthesize the corresponding udev events. Mirror the host's udev
  # records so libinput can classify the passed devices.
  syncInputMetadata = pkgs.writeShellScript "sunshine-sync-input-metadata" ''
    set -eu
    shopt -s nullglob
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}

    install -d -m 0755 /run/udev/data
    for node in /dev/input/event*; do
      sys=/sys/class/input/''${node##*/}
      [ ${sunshineInputId} = beef:dead ] || continue
      record=c$(cat "$sys/dev" 2>/dev/null) || continue
      [ -r "/opt/host-udev-data/$record" ] || continue
      ln -sfnT "/opt/host-udev-data/$record" "/run/udev/data/$record"
    done
  '';

  # Incus has hung stopping this container when Sunshine's devices vanished as
  # init exited, so wait for it to remove their nodes first (at most 10s).
  drainInputNodes = pkgs.writeShellScript "sunshine-drain-input-nodes" ''
    shopt -s nullglob
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}

    pending() {
      for node in /dev/input/event*; do
        sys=/sys/class/input/''${node##*/}
        # Device gone, node not yet removed by Incus.
        [ -e "$sys" ] || return 0
        [ ${sunshineInputId} = beef:dead ] && return 0
      done
      return 1
    }

    for _ in $(seq 1 100); do
      pending || exit 0
      sleep 0.1
    done
    echo "Sunshine input nodes still present after 10s" >&2
  '';
in
{
  imports = [
    ./base
    ./nvidia-runtime.nix
    "${self}/modules/software/bundles/fonts.nix"
    "${self}/modules/software/bundles/gui-apps/gaming.nix"
    "${self}/modules/software/services/sunshine.nix"
  ];

  networking.hostName = "sunshine-nix";

  # Also brings the PipeWire, fonts, portals and Xwayland the session needs.
  programs.labwc.enable = true;
  programs.firefox.enable = true;

  software.apps.gaming.enable = true;
  software.fonts.enable = true;

  # nvidia-runtime.nix bind-mounts the host driver over /run/opengl-driver, so
  # the guest must not build its own. programs/steam.nix still reads package
  # and package32, which graphics.nix only defines when enabled.
  hardware.graphics = {
    enable = lib.mkForce false;
    package = pkgs.mesa;
    package32 = pkgs.pkgsi686Linux.mesa;
  };

  services.sunshine = {
    # nixpkgs builds Sunshine without CUDA, so DMA-BUF capture on a pure-NVIDIA
    # host falls back to a software converter that fails every frame. The
    # patches let Sunshine start with no compositor and probe encoders only
    # after the prep commands have started the one being captured.
    package = sunshinePackage;

    # wlr capture does not need CAP_SYS_ADMIN. Avoiding the capability wrapper
    # also preserves the EGL loader environment for Sunshine.
    capSysAdmin = lib.mkForce false;

    settings = {
      sunshine_name = "sunshine-nix";
      capture = "wlr";
      output_name = streamOutput;
      csrf_allowed_origins = lib.concatMapStringsSep "," (host: "https://${host}:47990") [
        "${config.networking.hostName}.lan"
        (networkTopology.lib.lanIp config.networking.hostName)
      ];
      system_tray = "disabled";
    };

    applications.apps = [
      {
        name = "Desktop";
        prep-cmd = [
          {
            do = "${streamSession} start desktop";
            undo = "${streamSession} stop";
          }
        ];
      }
      {
        name = "RuneLite";
        prep-cmd = [
          {
            do = "${streamSession} start runelite";
            undo = "${streamSession} stop";
          }
        ];
        cmd = "${streamSession} wait runelite";
        auto-detach = "false";
      }
    ];
  };

  # GTK apps take their cursor from GSettings rather than XCURSOR_*.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        cursor-theme = cursorTheme;
        cursor-size = lib.gvariant.mkInt32 cursorSize;
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    boltLauncher
    comixcursors.Opaque_Orange
    foot
    fuzzel
    wlr-randr
    libxcb-cursor
  ];

  users.users.${user} = {
    inherit uid;
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

  # No display manager or login shell sets up this lingering user manager.
  # RuneLite runs sandboxed, where /etc/localtime resolves to a dangling
  # symlink and Java silently falls back to GMT, so TZ has to be explicit.
  # LD_LIBRARY_PATH is session-wide because the GLX vendor libraries are
  # unloadable for every X11 client without it.
  systemd.user.extraConfig = ''
    DefaultEnvironment=XDG_DATA_DIRS=/etc/profiles/per-user/${user}/share:/run/current-system/sw/share TZ=${config.time.timeZone} TZDIR=${pkgs.tzdata}/share/zoneinfo LD_LIBRARY_PATH=${glxClientLibraries}:/run/opengl-driver/lib
  '';

  # Without linger, user services never start on this headless container.
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/${user} 0644 root root -"
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
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${syncInputMetadata}";
    };
  };

  systemd.services.sunshine-input-drain = {
    description = "Wait for Incus to remove Sunshine's input devices";
    wantedBy = [ "multi-user.target" ];
    # Stops after the user manager, so after Sunshine has exited.
    before = [ "user@${toString uid}.service" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${drainInputNodes}";
    };
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

  systemd.user.services =
    lib.mapAttrs' (
      name: command:
      lib.nameValuePair "stream-${name}" {
        description = "Streamed ${name} session";
        unitConfig.ConditionUser = user;
        # A switch must not kill the apps in a live stream.
        restartIfChanged = false;
        path = [
          "/run/wrappers"
          config.system.path
        ];
        environment = compositorEnvironment;
        serviceConfig = {
          ExecStart = command;
          TimeoutStopSec = "10s";
        };
      }
    ) streamSessions
    // {
      # Starts with no compositor; each app's prep command brings one up.
      sunshine = {
        wantedBy = lib.mkForce [ "default.target" ];
        unitConfig.ConditionUser = user;
        partOf = lib.mkForce [ ];
        wants = lib.mkForce [ ];
        after = lib.mkForce [ ];
        environment = nvidiaGraphicsEnvironment // {
          WAYLAND_DISPLAY = waylandDisplay;
          XDG_SESSION_TYPE = "wayland";
          # FFmpeg dlopens libcuda.so.1, which ships only in the Incus driver
          # mount and is missing from the guest loader cache, so NVENC probing
          # fails without it. A unit's Environment= replaces DefaultEnvironment.
          LD_LIBRARY_PATH = "${glxClientLibraries}:/run/opengl-driver/lib";
        };
        serviceConfig.Restart = lib.mkForce "always";
      };
    };
}
