{
  config,
  lib,
  self,
  pkgs,
  ...
}:

let
  user = "taylor";
  waylandDisplay = "wayland-1";
  defaultResolution = "1920x1080";
  defaultFps = "60";

  sessionEnvironment = {
    DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    KDE_FULL_SESSION = "true";
    KDE_SESSION_VERSION = "6";
    KWIN_WAYLAND_VIRTUAL_SCREENS = "1";
    KWIN_WAYLAND_VIRTUAL_SCREEN_GEOMETRIES = defaultResolution;
    QT_QPA_PLATFORM = "wayland";
    WAYLAND_DISPLAY = waylandDisplay;
    XDG_CURRENT_DESKTOP = "KDE";
    XDG_SESSION_DESKTOP = "KDE";
    XDG_SESSION_TYPE = "wayland";
  };

  startVirtualMonitor = pkgs.writeShellScript "sunshine-start-virtual-monitor" ''
    set -eu

    resolution=''${SUNSHINE_VIRTUAL_MONITOR_RESOLUTION:-${defaultResolution}}
    exec ${lib.getExe' pkgs.kdePackages.krfb "krfb-virtualmonitor"} \
      --name sunshine \
      --resolution "$resolution" \
      --port 5905 \
      --password sunshine
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
    ../hardware/nvidia.nix
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
      output_name = "0";
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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
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

    path = with pkgs; [
      kdePackages.kwin
      kdePackages.plasma-workspace
      xwayland
    ];

    environment = sessionEnvironment;

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
      ExecStartPost = "${pkgs.systemd}/bin/systemctl --user start graphical-session.target";
      ExecStopPost = "${pkgs.systemd}/bin/systemctl --user stop graphical-session.target";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  systemd.user.services.sunshine-virtual-monitor = {
    description = "Sunshine KDE virtual monitor";
    wantedBy = [ "default.target" ];
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
      ExecStart = "${startVirtualMonitor}";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # Sunshine connects to the plasma Wayland session
  systemd.user.services.sunshine = {
    wantedBy = lib.mkForce [ "default.target" ];
    after = [
      "plasma-headless.service"
      "sunshine-virtual-monitor.service"
    ];
    wants = [
      "plasma-headless.service"
      "sunshine-virtual-monitor.service"
    ];
    environment = sessionEnvironment // {
      DISPLAY = ":0";
    };
  };

  warnings = lib.optional (lib.versionOlder pkgs.sunshine.version "2026.516.143833") ''
    sunshine-nix is configured for KDE/Wayland capture = "kwin", but the selected Sunshine package is ${pkgs.sunshine.version}.
    Use Sunshine >= 2026.516.143833 for KWin capture support.
  '';
}
