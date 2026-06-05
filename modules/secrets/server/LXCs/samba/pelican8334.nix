{ config, lib, ... }:

let
  cfg = config.my.secrets.pelican8334-pass;
in
{
  options.my.secrets.pelican8334-pass = {
    enable = lib.mkEnableOption "Secret for pelican8334 samba user password";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.pelican8334-pass = {
      sopsFile = ./pelican8334.yaml;
      neededForUsers = true;
    };
  };
}
