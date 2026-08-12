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
  defaultResolution = "1920x1080";
  defaultFps = "60";

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

  startVirtualMonitor = pkgs.writeShellScript "sunshine-start-virtual-monitor" ''
    set -eu

    resolution=''${SUNSHINE_VIRTUAL_MONITOR_RESOLUTION:-${defaultResolution}}

    exec ${lib.getExe' pkgs.kdePackages.krfb "krfb-virtualmonitor"} \
      --name sunshine \
      --resolution "$resolution" \
      --port 5905 \
      --password sunshine
  '';

  waitForVirtualMonitor = pkgs.writeShellScript "sunshine-wait-for-virtual-monitor" ''
    set -eu

    for _ in $(seq 1 60); do
      outputs="$(${pkgs.coreutils}/bin/timeout --kill-after=0.2s 0.5s \
        ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -o 2>/dev/null || true)"
      if printf '%s\n' "$outputs" \
        | ${pkgs.gnugrep}/bin/grep -q 'Virtual-sunshine'; then
        exit 0
      fi
      sleep 0.1
    done

    echo "Virtual-sunshine did not become ready" >&2
    exit 1
  '';

  setClientResolution = pkgs.writeShellScript "sunshine-set-client-resolution" ''
    set -eu

    width=''${SUNSHINE_CLIENT_WIDTH:-1920}
    height=''${SUNSHINE_CLIENT_HEIGHT:-1080}
    fps=''${SUNSHINE_CLIENT_FPS:-${defaultFps}}

    case "$width:$height:$fps" in
      (*[!0-9:]* | "" | *::*)
        echo "invalid Sunshine client geometry: $width x $height @ $fps" >&2
        exit 1
        ;;
    esac

    env_dir="$HOME/.config/sunshine"
    env_file="$env_dir/virtual-monitor.env"
    mkdir -p "$env_dir"
    printf 'SUNSHINE_VIRTUAL_MONITOR_RESOLUTION=%sx%s\n' "$width" "$height" > "$env_file.tmp"
    mv "$env_file.tmp" "$env_file"

    ${pkgs.systemd}/bin/systemctl --user restart sunshine-virtual-monitor.service

    # Give KWin/KScreen a moment to publish the recreated output before
    # Sunshine starts capturing it.
    for _ in $(seq 1 50); do
      if ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} -o 2>/dev/null | grep -q 'Virtual-sunshine'; then
        break
      fi
      sleep 0.1
    done

    ${lib.getExe' pkgs.kdePackages.libkscreen "kscreen-doctor"} \
      output.Virtual-sunshine.enable \
      output.Virtual-sunshine.primary \
      output.Virtual-sunshine.position.0,0 \
      output.Virtual-sunshine.scale.1 || true
  '';

  resetClientResolution = pkgs.writeShellScript "sunshine-reset-client-resolution" ''
    set -eu

    env_dir="$HOME/.config/sunshine"
    env_file="$env_dir/virtual-monitor.env"
    mkdir -p "$env_dir"
    printf 'SUNSHINE_VIRTUAL_MONITOR_RESOLUTION=${defaultResolution}\n' > "$env_file.tmp"
    mv "$env_file.tmp" "$env_file"

    ${pkgs.systemd}/bin/systemctl --user restart sunshine-virtual-monitor.service
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
    settings = {
      sunshine_name = "sunshine-nix";
      capture = "kwin";
      output_name = "Virtual-sunshine";
      csrf_allowed_origins = "https://sunshine-nix.lan:47990,https://10.73.73.140:47990";
      system_tray = "disabled";
    };

    applications.apps = [
      {
        name = "Desktop";
        prep-cmd = [
          {
            do = "${setClientResolution}";
            undo = "${resetClientResolution}";
          }
        ];
        exclude-global-prep-cmd = "false";
        auto-detach = "true";
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    kdePackages.krfb
    kdePackages.libkscreen
    kdePackages.kscreen
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
  # display attached, so use KWin's supported virtual framebuffer backend and
  # give the session the stable socket name consumed by Sunshine and krfb.
  systemd.user.services.plasma-kwin_wayland = {
    # The wrapper starts kwin_wayland and Xwayland by name. This unit otherwise
    # receives only systemd's basic PATH and silently remains as a socket-owning
    # wrapper with no compositor behind it.
    path = [
      pkgs.kdePackages.kwin
      pkgs.xwayland
    ];
    environment = sessionEnvironment;

    serviceConfig.ExecStart = lib.mkForce (
      "${lib.getExe' pkgs.kdePackages.kwin "kwin_wayland_wrapper"} "
      + "--xwayland --virtual --width 1920 --height 1080 --scale 1 "
      + "--no-lockscreen"
    );
  };

  systemd.user.services.sunshine-virtual-monitor = {
    description = "Sunshine KDE virtual monitor";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = user;
    after = [
      "plasma-headless.service"
      "graphical-session.target"
    ];
    wants = [ "plasma-headless.service" ];
    partOf = [ "plasma-headless.service" ];

    environment = sessionEnvironment;

    serviceConfig = {
      Type = "simple";
      EnvironmentFile = "-%h/.config/sunshine/virtual-monitor.env";
      ExecStartPre = "${waitForKWin}";
      ExecStart = "${startVirtualMonitor}";
      Restart = "on-failure";
      RestartSec = "5";
      TimeoutStopSec = "5s";
    };
  };

  # Sunshine connects to the plasma Wayland session
  systemd.user.services.sunshine = {
    wantedBy = lib.mkForce [ "default.target" ];
    unitConfig.ConditionUser = user;
    partOf = lib.mkForce [ ];
    wants = lib.mkForce [
      "plasma-headless.service"
      "sunshine-virtual-monitor.service"
    ];
    after = lib.mkForce [
      "plasma-headless.service"
      "sunshine-virtual-monitor.service"
    ];
    environment = sessionEnvironment // {
      DISPLAY = ":0";
    };
    serviceConfig = {
      ExecStartPre = [ "${waitForVirtualMonitor}" ];
      Restart = lib.mkForce "always";
    };
  };

  warnings = lib.optional (lib.versionOlder pkgs.sunshine.version "2026.516.143833") ''
    sunshine-nix is configured for KDE/Wayland capture = "kwin", but the selected Sunshine package is ${pkgs.sunshine.version}.
    Use Sunshine >= 2026.516.143833 for KWin capture support.
  '';
}
