{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/romm.nix"
  ];
  my.secrets.romm_env.enable = true;
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
