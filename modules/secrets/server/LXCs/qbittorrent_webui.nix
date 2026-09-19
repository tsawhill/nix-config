{ config, lib, ... }:

let
  cfg = config.my.secrets.qbittorrent_webui;
in
{
  options.my.secrets.qbittorrent_webui = {
    enable = lib.mkEnableOption "Secret for the qBittorrent web UI password hash";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.qbittorrent_webui_password = {
      sopsFile = ./qbittorrent_webui.yaml;
      key = "password_pbkdf2";
      mode = "0400";
      restartUnits = [ "qbittorrent.service" ];
    };
  };
}
