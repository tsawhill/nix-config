{ config, lib, ... }:

let
  cfg = config.my.secrets.qbittorrent_webui;

  # One file, one key per host. Both hosts are recipients of it either way, so
  # splitting into separate files would not buy isolation.
  mkPasswordSecret = key: {
    sopsFile = ./qbittorrent_webui.yaml;
    inherit key;
    mode = "0400";
    restartUnits = [ "qbittorrent.service" ];
  };
in
{
  options.my.secrets.qbittorrent_webui = {
    enable = lib.mkEnableOption "Secrets for the qBittorrent web UI password hashes";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      qbittorrent_webui_password_gen = mkPasswordSecret "password_gen";
      qbittorrent_webui_password_lts = mkPasswordSecret "password_lts";
    };
  };
}
