{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/syncthing"
  ];

  my.syncthing = {
    enable = true;
    device = "server";
    user = "syncthing";
    group = "syncthing";
    credentialsFile = "${self}/modules/secrets/syncthing/syncthing-nix.yaml";
    # Optional per-host override of a share's local path, e.g.
    # sharePaths.roms = "/mnt/zpool/roms";
  };

  my.groups = {
    media = {
      enable = true;
      members = [
        "root"
        "syncthing"
      ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [
        "root"
        "syncthing"
      ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [
        "root"
        "syncthing"
      ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [
        "root"
        "syncthing"
      ];
      gid = 1003;
    };
    games = {
      enable = true;
      members = [
        "root"
        "syncthing"
      ];
      gid = 1005;
    };
  };

  networking.hostName = "syncthing-nix";
}
