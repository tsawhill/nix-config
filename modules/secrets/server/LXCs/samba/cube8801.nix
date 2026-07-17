{ config, lib, ... }:

let
  cfg = config.my.secrets.cube8801-pass;
in
{
  options.my.secrets.cube8801-pass = {
    enable = lib.mkEnableOption "Secret for cube8801 samba user password";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.cube8801-pass = {
      sopsFile = ./cube8801.yaml;
      neededForUsers = true;
    };
  };
}
