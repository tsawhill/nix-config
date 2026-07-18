{ self, ... }:
{
  imports = [ "${self}/modules/software/services/syncthing" ];

  # Joins the `gamesaves` share (see modules/.../syncthing/fleet.nix). That
  # membership auto-activates the game save links home-manager module, symlinking
  # RPCS3/RetroArch/PCSX2/Dolphin data dirs into the share so saves follow the
  # deck. The deck deliberately does NOT join `roms` (too large for local disk).
  my.syncthing = {
    enable = true;
    device = "deck";
    user = "taylor";
    group = "users";
    credentialsFile = "${self}/modules/secrets/syncthing/taylor-deck-nix.yaml";
  };
}
