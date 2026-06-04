{
  self,
  modulesPath,
  inputs,
  ...
}:

let
  desktopSSHUsers = [ "taylor" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "taylor-laptop-nix";
  system.stateVersion = "25.11";
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    # Boot
    ./system/boot.nix

    # Disks and alerts
    ./system/disks.nix
    ./system/samba.nix
    ./system/syncthing.nix
    # ./system/smart-alerts.nix
    # ./system/zfs-alerts.nix
    # ./system/zfs-scrub-trim.nix

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network
    ./system/networking.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"
    "${self}/modules/software/games"

    # Desktop
    "${self}/modules/software/desktop"

    # WireGuard
    "${self}/modules/network/wireguard/wg-remote.nix"

    # Hardware
    "${self}/modules/software/services/openrgb.nix"
    "${self}/modules/hardware/udev"

  ];
  # Required when using home-manager as a NixOS module with useUserPackages = true
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  desktop.hyprland.enable = true;
  services.upower.enable = true;

  software.dev.enable = true;
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.media-playback.enable = true;
  software.apps.media-creation.enable = true;
  software.apps.gaming.enable = true;
  software.games.entries.guitarHero3.lsfgVk.enable = true;
  software.apps.emulators.enable = true;
  software.apps.printing.enable = true;
  software.apps.tools.enable = true;

  my.secrets.sshclientkey.taylor-laptop-nix-taylor.enable = true;
  my.secrets.wireguard.taylor-laptop-nix.wg-remote.enable = true;
  my.secrets.steamgriddb_api_key.enable = true;
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
