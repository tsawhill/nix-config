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
  # Wine-prefix system directories that regenerate on every run and cause
  # endless sync conflicts. Excluding them keeps the actual game saves under
  # drive_c/users in sync while dropping the noise.
  wineSystemIgnores = [
    "wine/*/drive_c/windows"
    "wine/*/drive_c/Program Files"
    # "wine/*/drive_c/Program Files (x86)"
    "wine/*/drive_c/ProgramData"
    "wine/*/drive_c/vrclient"
    "wine/*/*.reg"
    "wine/*/version"
    "wine/*/config_info"
    "wine/*/tracked_files"
    "wine/*/.update-timestamp"
  ];
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
      addresses = [ "tcp://taylor-desktop-nix.lan:22000" ];
    };
    laptop = {
      id = "HOCFK67-H47WRO3-OJXHUQU-3LPLSPT-WNTINEJ-V5GO3RF-CAZBSWS-6Q4ZOQH";
      addresses = [ "tcp://taylor-laptop-nix.lan:22000" ];
    };
    server = {
      id = "DGGC7I2-VTFNYNL-QVTE4EQ-NXNJ4CH-HBI3XUR-4RE77KN-WLYCQ35-3R7UBAX";
      addresses = [ "tcp://syncthing-nix.lan:22000" ];
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
      ];
      overrides.server = "/mnt/zpool/gamesaves";
      # RetroArch keeps all config (incl. input binds) in one retroarch.cfg at
      # its dir root; saves/states live in subdirs. Excluding the cfg keeps
      # config per-host while still syncing the saves.
      ignores = wineSystemIgnores ++ [ "Emulators/RetroArch/retroarch.cfg" ];
    };
  };
}
