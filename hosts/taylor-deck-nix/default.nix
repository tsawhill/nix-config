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
  networking.hostName = "taylor-deck-nix";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.11";
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
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
    # see system/networking.nix to enable once you generate a deck AirVPN config.
    "${self}/modules/network/wireguard/wg-remote.nix"
    "${self}/modules/network/wireguard/airvpn.nix"

    # Hardware services
    "${self}/modules/hardware/udev"
  ];

  # Required when using home-manager as a NixOS module with useUserPackages = true
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # ---------------------------------------------------------------------------
  # Steam Deck UI (Game Mode) + KDE Plasma desktop session
  # ---------------------------------------------------------------------------
  jovian = {
    steam = {
      enable = true;
      autoStart = true; # boot straight into the Steam Deck UI
      user = "taylor";
      desktopSession = "plasma"; # "Switch to Desktop" lands in KDE Plasma
    };
    devices.steamdeck = {
      enable = true; # deck hardware: APU, controls, fan, backlight
      enableFwupdBiosUpdates = false;
    };
    decky-loader.enable = true; # plugin loader
    # jovian.steamos.useSteamOSConfig defaults to jovian.steam.enable (true).
  };
  desktop.kde.enable = true;

  # ---------------------------------------------------------------------------
  # Software set (follows the desktop/laptop, minus Hyprland)
  # ---------------------------------------------------------------------------
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.media-playback.enable = true;
  software.apps.gaming.enable = true;
  software.apps.emulators.enable = true;
  software.apps.tools.enable = true;

  # Deck panel is 1280x800; gamescope sessions render at native panel res.
  software.games.gamescope.resolutions = [
    {
      width = 1280;
      height = 800;
    }
  ];

  # Games kept on the deck's local disk launch from their localPath instead of
  # the Samba share (the deck isn't always on the LAN). Add entry ids here and
  # set `localPath` on each game once its files are copied to the deck, e.g.:
  #   software.games.localGames = [ "guitarHero3" "ps3GuitarHero3" ];
  software.games.localGames = [ ];

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

  my.secrets.sshclientkey.taylor-deck-nix-taylor.enable = true;
  my.secrets.wireguard.pubkeys.enable = true;
  my.secrets.wireguard.taylor-deck-nix.wg-remote.enable = true;
  my.secrets.steamgriddb_api_key.enable = true;
  # AirVPN (disabled until you create the deck's wg-airvpn.yaml + fill in the
  # tunnel address in system/networking.nix):
  # my.secrets.wireguard.taylor-deck-nix.wg-airvpn.enable = true;
}
