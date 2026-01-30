{ self, ... }:
{
  imports = [
    ./base
    ../hardware/nvidia.nix # Import NVIDIA driver configuration for transcoding support
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
