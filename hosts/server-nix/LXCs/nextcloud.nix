{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/nextcloud.nix"
  ];
  my.secrets.nextcloud_admin_pass.enable = true;
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
    documents = {
      enable = true;
      members = [
        "root"
        "nextcloud"
      ];
      gid = 1004;
    };
  };
  networking.hostName = "nextcloud-nix";
}
