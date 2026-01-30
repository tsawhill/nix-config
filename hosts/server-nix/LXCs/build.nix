{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/packages/gotify-cli.nix"
    "${self}/modules/software/packages/git.nix"
    "${self}/modules/software/services/rebuild-scripts.nix"
  ];
  my.groups = {
    code = {
      enable = true;
      members = [ "root" ];
      gid = 1003;
    };
  };
  networking.hostName = "build-nix";
}
