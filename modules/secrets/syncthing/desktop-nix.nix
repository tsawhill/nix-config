{ config, lib, ... }:
let
  cfg = config.my.secrets.syncthing.desktop-nix;
in
{
  options.my.secrets.syncthing.desktop-nix.enable =
    lib.mkEnableOption "Syncthing cert/key for desktop-nix";

  config = lib.mkIf cfg.enable {
    sops.secrets."syncthing_key" = {
      sopsFile = ./desktop-nix.yaml;
      path = "/etc/syncthing/key.pem";
      owner = "taylor";
      group = "users";
      mode = "0600";
    };
    sops.secrets."syncthing_cert" = {
      sopsFile = ./desktop-nix.yaml;
      path = "/etc/syncthing/cert.pem";
      owner = "taylor";
      group = "users";
      mode = "0644";
    };
  };
}
