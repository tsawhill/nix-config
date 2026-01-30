{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/samba"
  ];
  my.shares = {
    users = {
      immobile0783 = {
        enable = true;
        extraGroups = [
          "media"
          "download"
          "gameservers"
          "code"
        ];
      };
    };
    definitions = {
      nix-configs = {
        enable = true;
        path = "/mnt/zpool/nixosconfigs";
        users = [ "immobile0783" ];
      };
      media = {
        enable = true;
        path = "/mnt/zpool/media";
        users = [ "immobile0783" ];
        readOnly = true;
      };
    };
  };
  my.groups = {
    media = {
      enable = true;
      members = [ "root" ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [ "root" ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [ "root" ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [ "root" ];
      gid = 1003;
    };
  };

  networking.hostName = "samba-nix";
}
