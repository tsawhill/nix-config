{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/deluge.nix"
  ];

  my.groups.download = {
    enable = true;
    members = [ "root" ];
    gid = 1001;
  };
  networking.hostName = "deluge-nix";
}
