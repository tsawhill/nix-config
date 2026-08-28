{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/pyload.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };

  networking.hostName = "pyload-nix";
}
