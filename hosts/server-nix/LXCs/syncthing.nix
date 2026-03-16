{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/syncthing.nix"
  ];
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
