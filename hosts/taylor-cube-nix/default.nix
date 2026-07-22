{
  self,
  inputs,
  lib,
  ...
}:

let
  buildSSHUsers = [ "root" ];
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "taylor-cube-nix";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.11";
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

    # Desktop: KDE Plasma only (the desktop/ dir auto-imports SDDM + Hyprland,
    # which we do not want — Jovian's autoStart is incompatible with a display
    # manager).
    "${self}/modules/software/desktop/kde.nix"
    "${self}/modules/software/desktop/pipewire/base.nix"

    # WireGuard (remote tunnel home). AirVPN scaffolding is present but disabled —
    # see system/networking.nix to enable once you generate a cube AirVPN config.
    "${self}/modules/network/networkmanager/wireguard/wg-remote.nix"
    "${self}/modules/network/networkmanager/wireguard/airvpn.nix"
    "${self}/modules/network/networkmanager/wifi/known-networks.nix"

    # Hardware services
    "${self}/modules/hardware/udev"
  ];

  # Required when using home-manager as a NixOS module with useUserPackages = true
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # ---------------------------------------------------------------------------
  # Steam Machine UI (Game Mode) + KDE Plasma desktop session
  # ---------------------------------------------------------------------------
  jovian = {
    steam = {
      enable = true;
      autoStart = true; # boot straight into the Steam Big Picture UI
      user = "taylor";
      desktopSession = "plasma"; # "Switch to Desktop" lands in KDE Plasma
    };
    decky-loader.enable = true; # plugin loader
    # Not a Steam Deck, so no jovian.devices.steamdeck (Deck APU/controls/fan/
    # backlight). Use the mainline/stock NixOS kernel instead of the SteamOS
    # (neptune) kernel — that kernel is really meant for Deck hardware. Game Mode
    # / Big Picture still comes from jovian.steam above; it doesn't need it.
    steamos.useSteamOSConfig = false;
  };
  desktop.kde.enable = true;

  # ---------------------------------------------------------------------------
  # Software set (follows the deck, minus Deck-specific bits)
  # ---------------------------------------------------------------------------
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.media-playback.enable = true;
  software.apps.gaming.enable = true;
  software.apps.emulators.enable = true;
  software.apps.tools.enable = true;

  # No forced gamescope launcher resolutions — the session renders at the TV's
  # native (EDID) resolution.
  software.games.steamSync.stopSteamDuringSync = true;

  # Games (or whole platforms) kept on the cube's local SSD: they sync there via
  # the roms Syncthing share (into software.games.syncRoot, default
  # ~/Games/synced) and launch locally; everything else launches from the full
  # library over the /mnt/zpool/roms CIFS mount. De-selecting a game and
  # rebuilding deletes its local copy.
  software.games.syncGames = [ "guitarHero3" ];

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
