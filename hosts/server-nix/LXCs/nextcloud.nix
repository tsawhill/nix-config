{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/nextcloud.nix"
  ];
  my.groups = {
    media = {
      enable = true;
      members = [
        "root"
        "nextcloud"
      ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [
        "root"
        "nextcloud"
      ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [
        "root"
        "nextcloud"
      ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [
        "root"
        "nextcloud"
      ];
      gid = 1003;
    };
  };
  networking.hostName = "nextcloud-nix";
}
