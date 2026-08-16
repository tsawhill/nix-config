{ networkTopology }:

# Syncthing fleet registry.
#
# Single source of truth for the whole fleet. Every host that enables
# `my.syncthing` reads this file to learn the device IDs/addresses of its
# peers and which shares it participates in.
#
# To add a share: add an entry under `shares` with a default `path`, list the
# NixOS `members`, and add an `overrides.<device>` only for members whose local
# path differs from the default. External (non-NixOS) devices are not listed in
# shares — they declare which shares they join on their own device entry.
let
  inherit (networkTopology.lib) fqdn;

in
{
  # Devices in the fleet. IDs are public (derived from the device's public
  # cert) so they live here in the repo; only the private key.pem is a secret.
  #
  # External (non-NixOS) devices set `external = true`, have no managed path,
  # and list the `shares` they join. `addresses = [ ]` means dynamic discovery.
  devices = {
    desktop = {
      id = "IDOGGQJ-Z4EVOPR-E3J6QOF-W6HBIG6-5TKLON4-IAS7VFU-3S65YAN-OLGOPQT";
      addresses = [ "tcp://${fqdn "taylor-desktop-nix"}:22000" ];
    };
    laptop = {
      id = "HOCFK67-H47WRO3-OJXHUQU-3LPLSPT-WNTINEJ-V5GO3RF-CAZBSWS-6Q4ZOQH";
      addresses = [ "tcp://${fqdn "taylor-laptop-nix"}:22000" ];
    };
    deck = {
      # REPLACE with the deck's real device ID once its cert/key are generated
      # (`syncthing generate` then read the id, or the Web UI -> Actions -> Show ID).
      id = "5D7VEJQ-K26I3DA-IMVGXJM-JLNGOW3-5WF3OIF-2OEKC3D-OJBAEBM-MSSYUA5";
      addresses = [ "tcp://${fqdn "taylor-deck-nix"}:22000" ];
    };
    cube = {
      id = "4WLZTJW-OFH4YAC-663LY3B-WCJYXA4-HNCE2MH-CNNTI7P-3MFZYDB-R74OPAP";
      addresses = [ "tcp://${fqdn "taylor-cube-nix"}:22000" ];
    };
    server = {
      id = "DGGC7I2-VTFNYNL-QVTE4EQ-NXNJ4CH-HBI3XUR-4RE77KN-WLYCQ35-3R7UBAX";
      addresses = [ "tcp://${fqdn "syncthing-nix"}:22000" ];
    };
    thor = {
      id = "UZKUGQ5-YZUACUX-UM7UKVH-ODTT5B3-4SSZUJ6-YI7H4XH-WZXSJMM-3AWQOA6";
      addresses = [ ];
      external = true;
      shares = [
        "roms"
        "gamesaves"
      ];
    };
  };

  # Shares (syncthing folders). `path` is the default local path for every
  # member; `overrides.<device>` replaces it for members that differ.
  #
  # `ignores` is an optional list of raw .stignore lines (folder-root relative,
  # glob/regex per syncthing) common to every member of the share — those paths
  # are never synced by anyone. A host can add its own extra patterns on top via
  # `my.syncthing.extraIgnores.<share>`.
  shares = {
    # Selective, per-host local game sync (see modules/software/games). The server
    # is the canonical copy; opt-in hosts join to pull LOCAL copies of the games
    # they select, each restricting what it fetches via a generated .stignore and
    # syncing into its software.games.syncRoot (default /home/taylor/Games/synced).
    # `ignoreDelete` protects the master: a client — or the games prune — deleting a
    # local copy never removes it from the server, while adds/mods still sync both
    # ways. Do NOT add a host here to full-sync the multi-TB library; hosts read the
    # full library over the /mnt/zpool/roms CIFS share instead.
    roms = {
      path = "/home/taylor/Games/synced";
      members = [
        "server"
        "cube"
      ];
      overrides.server = "/mnt/zpool/roms";
      ignoreDelete = true;
    };
    gamesaves = {
      path = "/home/taylor/Games/saves";
      members = [
        "desktop"
        "laptop"
        "server"
        "deck"
        "cube"
      ];
      overrides.server = "/mnt/zpool/gamesaves";
      ignores = [
        "runelite/cache" # regenerable client cache
        "runelite/jagexcache" # regenerable asset cache
        # Skyrim's launcher rewrites this for whatever display it starts on.
        "wine/default/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition GOG/SkyrimPrefs.ini"
        # RetroArch whitelist: first match wins and `*` doesn't cross `/`, so
        # these `!` includes survive the trailing glob that drops the rest.
        "!Emulators/RetroArch/saves" # in-game saves (SRAM) - keep
        "!Emulators/RetroArch/states" # save states - keep
        "!Emulators/RetroArch/config" # per-core config overrides - keep
        "!Emulators/RetroArch/system" # core BIOS/firmware - keep
        "Emulators/RetroArch/*" # cores, playlists, thumbs, retroarch.cfg: host-bound or regenerable
        # Dolphin data dir (~/.local/share/dolphin-emu); saves and mods stay.
        "Emulators/Dolphin/Dump" # texture/frame dumps, debug only
        "Emulators/Dolphin/Logs" # logs
        "Emulators/Dolphin/ScreenShots" # screenshots
        # Dolphin config dir (~/.config/dolphin-emu). Alone among these, Dolphin
        # splits graphics into its own GFX.ini, so video can stay per-host while
        # the controller binds in GCPadNew.ini/WiimoteNew.ini still sync.
        "Emulators/DolphinConfig/GFX.ini" # per-host GPU/resolution settings
        "Emulators/DolphinConfig/Logs" # logs
        # PCSX2: inis/PCSX2.ini mixes graphics with pad binds, so settings stay.
        "Emulators/PCSX2/cache" # game-list cache, rebuilt on scan
        "Emulators/PCSX2/logs" # logs
        "Emulators/PCSX2/snaps" # screenshots
        "Emulators/PCSX2/covers" # downloadable cover art
        "Emulators/PCSX2/videos" # capture output
        # RPCS3 blacklist: video settings share config.yml with core/audio/input,
        # so settings can't be split out - only dead weight is dropped here.
        "Emulators/RPCS3/captures" # RSX frame captures, debug only
        "Emulators/RPCS3/recordings" # gameplay capture output
        "Emulators/RPCS3/GuiConfigs" # window geometry and GUI state
        # Ryujinx: Config.json mixes graphics with input, same as RPCS3.
        "Emulators/Ryujinx/games" # per-title PPTC + shader caches, GPU-bound
        "Emulators/Ryujinx/Logs" # logs
        "Emulators/Ryujinx/screenshots" # screenshots
      ];
    };
  };
}
