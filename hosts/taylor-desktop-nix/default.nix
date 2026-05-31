{
  self,
  inputs,
  lib,
  ...
}:
let
  buildSSHUsers = [ "root" ];
  laptopSSHUsers = [ "taylor" ];
  phoneSSHUsers = [ "taylor" ];

in
{
  networking.hostName = "taylor-desktop-nix";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.11";

  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-unstable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix

    # Hardware
    ./system/boot.nix
    ./system/disks.nix
    ./system/hardware
    ./system/lact.nix
    ./system/networking.nix
    ./system/syncthing.nix
    ./system/samba.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
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
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"

    # Desktop
    "${self}/modules/software/desktop"

    # WireGuard
    "${self}/modules/network/wireguard/wg-remote.nix"
    "${self}/modules/network/wireguard/airvpn.nix"

    # Hardware services
    # "${self}/modules/software/services/openrgb.nix"
    "${self}/modules/hardware/udev"
  ];

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  desktop.hyprland.enable = true;
  my.desktop.audio.motuMic.enable = true;
  my.desktop.audio.lowLatency = {
    enable = true;
    quantum = 128;
  };

  software.lan-launch = {
    interfaces = [ "eno2" ];
    users = [ "taylor" ];
  };

  software.dev.enable = true;
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication = {
    enable = true;
    vesktop = {
      env = {
        DRI_PRIME = "pci-0000_6f_00_0";
        LIBVA_DRIVER_NAME = "radeonsi";
        NIXOS_OZONE_WL = "1";
      };
      extraFlags = [
        "--enable-features=VaapiVideoEncoder,WebRTCPipeWireCapturer"
        "--ignore-gpu-blocklist"
      ];
    };
  };
  software.apps.media-playback.enable = true;
  software.apps.media-creation.enable = true;
  software.apps.gaming = {
    enable = true;
    lsfgVk.enable = true;
  };
  software.apps.emulators.enable = true;
  software.apps.printing.enable = true;
  software.apps.tools.enable = true;

  my.secrets.syncthing.desktop-nix.enable = true;
  my.secrets.sshclientkey.taylor-desktop-nix-taylor.enable = true;
  my.secrets.wireguard.taylor-desktop-nix.wg-remote.enable = true;
  my.secrets.wireguard.taylor-desktop-nix.wg-airvpn.enable = true;

  my.users.taylor = {
    enable = true;
    extraGroups = [
      "i2c"
      "input"
      "video"
    ];
    sudoer = true;
  };
}
