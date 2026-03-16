{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/romm.nix"
  ];
  my.groups = {
    games = {
      enable = true;
      members = [
        "root"
        "romm"
      ];
      gid = 1005;
    };
  };

  networking.hostName = "romm-nix";
}
