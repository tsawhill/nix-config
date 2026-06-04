# Syncthing fleet registry.
#
# Single source of truth for the whole fleet. Every host that enables
# `my.syncthing` reads this file to learn the device IDs/addresses of its
# peers and which shares it participates in.
#
# To add a share: add an entry under `shares` and map each participating
# device to its default local path (or `null` for external/unmanaged devices).
# Any host can override its own path via `my.syncthing.sharePaths.<share>`.
{
  # Devices in the fleet. IDs are public (derived from the device's public
  # cert) so they live here in the repo; only the private key.pem is a secret.
  # `addresses = [ ]` means dynamic discovery (used for external devices).
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
    # External (non-NixOS) device: Android phone. Not assigned to any host.
    thor = {
      id = "UZKUGQ5-YZUACUX-UM7UKVH-ODTT5B3-4SSZUJ6-YI7H4XH-WZXSJMM-3AWQOA6";
      addresses = [ ];
    };
  };

  # Shares (syncthing folders). Each share maps the devices that participate
  # to their default local path. `null` = a member for trust purposes whose
  # path is managed elsewhere (e.g. on the phone).
  shares = {
    roms = {
      devices = {
        desktop = "/home/taylor/Games/roms";
        laptop = "/home/taylor/Games/roms";
        server = "/mnt/zpool/roms";
        thor = null;
      };
    };
    gamesaves = {
      devices = {
        desktop = "/home/taylor/Games/saves";
        laptop = "/home/taylor/Games/saves";
        server = "/mnt/zpool/gamesaves";
        thor = null;
      };
    };
  };
}
