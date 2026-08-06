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

    # Desktop: the whole desktop/ dir — KDE Plasma, Hyprland, SDDM, and the full
    # PipeWire stack (virtual sinks + mic chain). GNOME is in there too but stays
    # gated behind desktop.gnome.enable.
    #
    # TEMPORARY (2026-07-31): the cube is standing in as the primary workstation
    # while taylor-desktop-nix is torn down. That requires a display manager, so
    # jovian.steam.autoStart is off below — Jovian's autoStart and a DM cannot
    # both own the session. To revert to a console-only box: restore the
    # KDE-only imports (kde.nix + pipewire/base.nix), drop desktop.hyprland,
    # and set jovian.steam.autoStart back to true.
    "${self}/modules/software/desktop"

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
      # TEMPORARY: off while the cube is the primary workstation, so SDDM can
      # autologin straight into Hyprland. Big Picture is still available as an
      # SDDM session and from the Steam client. Set back to true to boot into
      # Game Mode again.
      autoStart = false;
      user = "taylor";
      desktopSession = "hyprland-uwsm"; # "Switch to Desktop" lands in Hyprland
    };
    decky-loader.enable = true; # plugin loader
    # Not a Steam Deck, so no jovian.devices.steamdeck (Deck APU/controls/fan/
    # backlight). Use the mainline/stock NixOS kernel instead of the SteamOS
    # (neptune) kernel — that kernel is really meant for Deck hardware. Game Mode
    # / Big Picture still comes from jovian.steam above; it doesn't need it.
    steamos.useSteamOSConfig = false;
  };
  desktop.kde.enable = true;
  desktop.hyprland.enable = true;

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
  # TEMPORARY (primary-workstation stint): dev tooling, previously desktop-only.
  software.dev.enable = true;

  # Audio: same layout as taylor-desktop-nix — game/discord/desktop virtual
  # sinks plus a mic_input source. The motuMic filter chain's capture node
  # autoconnects to the default source, so it works whether or not the M2 is
  # physically attached.
  my.desktop.audio.motuMic.enable = true;
  my.desktop.audio.lowLatency = {
    enable = true;
    quantum = 128;
  };

  # No forced gamescope launcher resolutions — the session renders at the TV's
  # native (EDID) resolution.
  software.games.steamSync.stopSteamDuringSync = true;

  # Games (or whole platforms) kept on the cube's local SSD: they sync there via
  # the roms Syncthing share (into software.games.syncRoot, default
  # ~/Games/synced) and launch locally; everything else launches from the full
  # library over the /mnt/zpool/roms CIFS mount. Keep pc selective so only GH3
  # syncs from that platform.
  software.games.syncGames = [ "guitarHero3" ];
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
