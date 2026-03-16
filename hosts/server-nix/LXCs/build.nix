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
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  networking.hostName = "build-nix";
}
