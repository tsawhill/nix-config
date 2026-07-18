{ self, ... }:
{
  imports = [ "${self}/modules/software/services/syncthing" ];

  # Joins the `gamesaves` share (see modules/.../syncthing/fleet.nix). That
  # membership auto-activates the emulator-saves home-manager module, symlinking
  # RPCS3/RetroArch/PCSX2/Dolphin data dirs into the share so saves follow the
  # cube. Deliberately does NOT join `roms` (too large for the local disk).
  my.syncthing = {
    enable = true;
    device = "cube";
    user = "taylor";
    group = "users";
    guiAddress = "0.0.0.0:8384";
    credentialsFile = "${self}/modules/secrets/syncthing/taylor-cube-nix.yaml";
  };
}
