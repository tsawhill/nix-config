{ config, lib, ... }:

let
  cfg = config.my.secrets.umbriel-pass;
in
{
  options.my.secrets.umbriel-pass = {
    enable = lib.mkEnableOption "Secret for umbriel samba user password";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.umbriel-pass = {
      sopsFile = ./umbriel.yaml;
      neededForUsers = true;
    };
  };
}
