{
  self,
  inputs,
  lib,
  ...
}:

# TEMPORARY: taylor-desktop-nix is torn down for a watercooling rebuild (from
# 2026-09-12, expected ~1 week), so this host stands in for it — the desktop's
# session, software set and Hyprland layout on the cube's own hardware.
# Everything hardware- or storage-bound stays cube-local: Jovian's steammachine
# profile, boot/disks/networking, the Lexar SD sync root, and the cube's samba
# credentials. Revert this commit when the desktop comes back.

let
  buildSSHUsers = [ "root" ];
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "taylor-cube-nix";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
  nixpkgs.config.permittedInsecurePackages = [
    "pnpm-9.15.9"
  ];

  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-unstable.nixosModules.sops
    "${self}/modules/secrets"

    # Jovian-NixOS (Steam Deck UI / Game Mode)
    inputs.jovian.nixosModules.default

    # Home Manager
    ./home-manager.nix

    # Hardware / system
    ./system/hardware
    ./system/boot.nix
    ./system/disks.nix
    ./system/networking.nix
    ./system/samba.nix
    ./system/syncthing.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/cachix.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"
    "${self}/modules/software/games"

    # Desktop: the whole dir, same as taylor-desktop-nix — SDDM + Hyprland + KDE
    # and the full pipewire set (virtual sinks and mic, not just base +
    # low-latency). Only safe because jovian.steam.autoStart is off below:
    # Jovian claims services.displayManager for itself when autoStart is on,
    # which is why this used to be a cherry-picked list. Also brings
    # desktop/usbip.nix, so the explicit usbip-tray import is no longer needed.
    "${self}/modules/software/desktop"

    # WireGuard (remote tunnel home). AirVPN scaffolding is present but disabled —
    # see system/networking.nix to enable once you generate a cube AirVPN config.
    "${self}/modules/network/networkmanager/wireguard/wg-remote.nix"
    "${self}/modules/network/networkmanager/wireguard/airvpn.nix"
    "${self}/modules/network/networkmanager/wifi/known-networks.nix"

    # Hardware services
    "${self}/modules/hardware/bluetooth.nix"
    "${self}/modules/hardware/udev"
    "${self}/modules/hardware/lexar-sd.nix"
  ];

  # Both directions: the cube shares its own ports and receives from others.
  my.usbip.enable = true;

  my.lexarSD.enable = true;

  # Required when using home-manager as a NixOS module with useUserPackages = true
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # ---------------------------------------------------------------------------
  # Session: Hyprland via SDDM (desktop stand-in), Game Mode still available
  # ---------------------------------------------------------------------------
  jovian = {
    steam = {
      enable = true;
      # Off for the stand-in. With autoStart on, Jovian sets
      # services.displayManager.{sddm.enable, autoLogin, defaultSession =
      # "gamescope-wayland"} and collides with
      # modules/software/desktop/display-manager.nix. Game Mode is still built:
      # log out and pick the "gamescope-wayland" session at the SDDM greeter.
      autoStart = false;
      user = "taylor";
      # desktopSession is deliberately unset: Jovian only consumes it under
      # autoStart and warns at eval time if it is set without it. Restore
      # `desktopSession = "hyprland-uwsm"` together with autoStart = true.
    };
    decky-loader.enable = true; # plugin loader

    # Steam Machine (Fremont) profile: the jovian kernel, HID preloads, initrd
    # storage modules, valve-leds permissions and brightness slider, and — the
    # point of the exercise — early modesetting defaulted off so cros_ec_cec
    # registers its named "Port C" notifier before amdgpu registers an unnamed
    # one and strands the CEC adapter at f.f.f.f. Also sets has.amd.gpu.
    devices.steammachine.enable = true;

    # Deck hardware (neptune kernel, firmware, controller, fan, gyro) is gated by
    # jovian.devices.steamdeck, left off. useSteamOSConfig only bundles opinionated
    # SteamOS tweaks, so opt in per-option and skip the Deck-only ones.
    steamos = {
      useSteamOSConfig = false;
      enableDefaultCmdlineConfig = true;
      enableSysctlConfig = true;
      enableEarlyOOM = true;
      enableBluetoothConfig = true;
      enableProductSerialAccess = true;
      enableZram = true;
      enableHdmiCecIntegration = true;
      # enableAutoMountUdevRules: jupiter-hw-support, Deck SD slot only — removable
      # media gets explicit mounts instead (see modules/hardware/lexar-sd.nix).
    };
  };

  # Jovian setcaps gamescope unconditionally, which aborts under Steam's
  # no-new-privs sandbox and kills any game launched via a gamescope launch option.
  security.wrappers.gamescope.capabilities = lib.mkForce "";

  # Steam's FHS sandbox maps only uid 1000, so a root-owned /tmp/.X11-unix reads as
  # nobody inside it and wlroots refuses to start gamescope's Xwayland. Own it as taylor.
  systemd.tmpfiles.rules = [ "d /tmp/.X11-unix 1777 taylor users -" ];

  desktop.hyprland.enable = true;
  desktop.kde.enable = true; # still selectable at the SDDM greeter
  desktop.plymouth.enable = true;

  # Moonlight's native Wayland path changes brightness during window resizing on
  # the HDR Alienware panels, which are now cabled here. XWayland keeps the
  # brightness stable.
  nixpkgs.overlays = [
    (_final: prev: {
      moonlight-qt = prev.moonlight-qt.overrideAttrs (old: {
        qtWrapperArgs = (old.qtWrapperArgs or [ ]) ++ [ "--set QT_QPA_PLATFORM xcb" ];
      });
    })
  ];

  # DrKonqi's dialog has no display in Game Mode: each crash report crashes and
  # spawns another, which is how the user manager collected 130k failed units.
  systemd.services."drkonqi-coredump-processor@".wantedBy = lib.mkForce [ ];

  # MOTU M2 interface moved over from the desktop along with the monitors.
  my.desktop.audio.motuMic.enable = true;
  my.desktop.audio.lowLatency = {
    enable = true;
    quantum = 128;
    alsaHeadroom = 0;
    # Recording is not latency-sensitive; batch its PulseAudio capture in
    # 10.7 ms chunks while interactive streams keep the 128-sample quantum.
    pulseCaptureQuantumByProcess.gpu-screen-recorder = 512;
  };

  # ---------------------------------------------------------------------------
  # Software set (desktop's, minus printing and media-creation)
  # ---------------------------------------------------------------------------
  software.dev.enable = true;
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.vesktop = {
    enable = true;
    hardwareVideoEncode = {
      enable = true;
      # The cube is single-GPU at 0000:03:00.0 (1002:7481); the desktop's
      # pci-0000_6f_00_0 does not exist here.
      driPrime = "pci-0000_03_00_0";
      vaDriver = "radeonsi";
    };
  };
  software.apps.media-playback.enable = true;
  software.apps.gaming = {
    enable = true;
    lsfgVk.enable = true;
  };
  software.apps.emulators.enable = true;
  software.apps.tools.enable = true;
  software.games.lsfgVk.enable = true;

  software.games.steamSync.stopSteamDuringSync = true;

  # The desktop's Alienware panels are cabled here for the rebuild, so the
  # gamescope launchers take its resolutions instead of the TV's EDID native.
  software.games.gamescope.resolutions = [
    {
      width = 2560;
      height = 1440;
      refresh = 360;
    }
    {
      width = 3440;
      height = 1440;
      refresh = 165;
    }
  ];
  # GH3 stays on its prior resolutions rather than following the global default.
  software.games.entries.guitarHero3.gamescope.resolutions = [
    {
      width = 1920;
      height = 1440;
      refresh = 360;
    }
    {
      width = 2560;
      height = 1440;
      refresh = 360;
    }
  ];

  # Games (or whole platforms) kept on the cube's Lexar SD card: they sync there
  # via the roms Syncthing share (syncRoot below feeds my.syncthing.sharePaths.roms)
  # and launch locally; everything else launches from the full library over the
  # /mnt/zpool/roms CIFS mount. Keep pc selective so only GH3 syncs from that
  # platform. Cube-local storage — do NOT repoint at the desktop's default while
  # standing in, or Syncthing deletes the ~576 GB already on the card.
  software.games.syncRoot = "/mnt/lexarSD/Games/synced";
  software.games.syncGames = [
    "guitarHero3"
    "guitarHeroWorldTourDefinitiveEdition"
    "guitarHeroWorldTourDefinitiveEditionUpdater"
    "skyrimAnniversaryEdition"
    "skyrimAnniversaryEditionLauncher"
  ];
  software.games.syncPlatforms = [
    "3ds"
    "arcade"
    "n64"
    "nds"
    "nes"
    "ngc"
    "ps2"
    "ps3"
    "snes"
    "switch"
    "wii"
    "wiiu"
  ];

  # ---------------------------------------------------------------------------
  # User + secrets
  # ---------------------------------------------------------------------------
  my.users.taylor = {
    enable = true;
    extraGroups = [
      "input"
      "video"
    ];
    sudoer = true;
  };

  my.secrets.sshclientkey.taylor-cube-nix-taylor.enable = true;
  my.secrets.networkmanager.wifi.known-networks.enable = true;
  my.secrets.wireguard.pubkeys.enable = true;
  my.secrets.wireguard.taylor-cube-nix.wg-remote.enable = true;
  my.secrets.steamgriddb_api_key.enable = true;
  # AirVPN (disabled until you create the cube's wg-airvpn.yaml + fill in the
  # tunnel address in system/networking.nix):
  # my.secrets.wireguard.taylor-cube-nix.wg-airvpn.enable = true;
}
