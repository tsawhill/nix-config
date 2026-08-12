{ self, ... }:
{
  imports = [
    ./base
    ./nvidia-runtime.nix
    "${self}/modules/software/services/jellyfin.nix"
  ];
  my.groups = {
    media = {
      enable = true;
      members = [ "root" ];
      gid = 1000;
    };
  };
  networking.hostName = "jellyfin-nix";
}
