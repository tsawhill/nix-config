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
    roms = {
      path = "/home/taylor/Games/roms";
      members = [
        "desktop"
        "laptop"
        "server"
      ];
      overrides.server = "/mnt/zpool/roms";
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
      # RetroArch keeps all config (incl. input binds) in one retroarch.cfg at
      # its dir root; saves/states live in subdirs. Excluding the cfg keeps
      # config per-host while still syncing the saves.
      ignores = [
        # RuneLite regenerable caches — no point syncing.
        "runelite/cache"
        "runelite/jagexcache"
        # RetroArch: sync only saves/states/config. Everything else is
        # regenerable, downloadable, platform-specific (cores!), or path-bound
        # (playlists). First match wins and `*` doesn't cross `/`, so these
        # `!` includes keep those dirs (and their contents) while the trailing
        # glob drops every other top-level RetroArch entry, incl. retroarch.cfg.
        "!Emulators/RetroArch/saves"
        "!Emulators/RetroArch/states"
        "!Emulators/RetroArch/config"
        "Emulators/RetroArch/*"
      ];
    };
  };
}
