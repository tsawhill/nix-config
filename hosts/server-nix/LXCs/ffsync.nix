{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/ffsync.nix"
  ];
  my.secrets.ffsync_env.enable = true;
  networking.hostName = "ffsync-nix";
}
