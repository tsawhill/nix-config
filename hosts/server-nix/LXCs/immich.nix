{ self, ... }:
{
  imports = [
    ./base
    ./nvidia-runtime.nix
    "${self}/modules/software/services/immich.nix"
  ];
  users.users.immich.extraGroups = [
    "video"
    "render"
  ];
  my.groups = {
    media = {
      enable = true;
      members = [ "root" ];
      gid = 1000;
    };
  };

  networking.hostName = "immich-nix";
}
