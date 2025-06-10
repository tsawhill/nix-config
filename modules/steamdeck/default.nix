{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./jovian.nix
    ./hardware-configuration.nix
    ./user_definition
    ./system
  ];
  system.stateVersion = "24.11";

  # Enable sdcard mount
  fileSystems."/mnt/sdcard" = {
    device = "/dev/disk/by-id/mmc-LX1TB_0x378801e2-part1";
    fsType = "ext4";
    options = [
      "rw"
      "users"
      "exec"
      "nofail"
      "x-gvfs-show"
    ];
  };

}
