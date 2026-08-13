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

  waitForVirtualOutput = pkgs.writeShellScript "sunshine-wait-for-virtual-output" ''
    set -eu

    for _ in $(seq 1 60); do
      outputs="$(${pkgs.coreutils}/bin/timeout --kill-after=0.2s 0.5s \
        ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -o 2>/dev/null || true)"
      if printf '%s\n' "$outputs" \
        | ${pkgs.gnugrep}/bin/grep -q 'Virtual-0'; then
        exit 0
      fi
      sleep 0.1
    done

    echo "Virtual-0 did not become ready" >&2
    exit 1
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
      output_name = "Virtual-0";
      csrf_allowed_origins = "https://sunshine-nix.lan:47990,https://10.73.73.140:47990";
      system_tray = "disabled";
    };

    applications.apps = [
      {
        name = "Desktop";
        auto-detach = "true";
      }
    ];
  };

  environment.systemPackages = with pkgs; [
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

  # The stock Plasma unit starts KWin's DRM backend. This LXC has no physical
  # display attached, so use KWin's supported virtual framebuffer backend.
  systemd.user.services.plasma-kwin_wayland = {
    # The wrapper starts kwin_wayland and Xwayland by name. This unit otherwise
    # receives only systemd's basic PATH and silently remains as a socket-owning
    # wrapper with no compositor behind it.
    path = [
      pkgs.kdePackages.kwin
      pkgs.xwayland
    ];
    environment = sessionEnvironment // nvidiaGraphicsEnvironment;

    serviceConfig.ExecStart = lib.mkForce (
      "${lib.getExe' pkgs.kdePackages.kwin "kwin_wayland_wrapper"} "
      + "--xwayland --virtual --width 1920 --height 1080 --scale 1 "
      + "--no-lockscreen"
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
        "${waitForVirtualOutput}"
      ];
      Restart = lib.mkForce "always";
    };
  };

  warnings = lib.optional (lib.versionOlder pkgs.sunshine.version "2026.516.143833") ''
    sunshine-nix is configured for KDE/Wayland capture = "kwin", but the selected Sunshine package is ${pkgs.sunshine.version}.
    Use Sunshine >= 2026.516.143833 for KWin capture support.
  '';
}
