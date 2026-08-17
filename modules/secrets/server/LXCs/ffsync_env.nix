{ config, lib, ... }:

let
  cfg = config.my.secrets.ffsync_env;
in
{
  options.my.secrets.ffsync_env = {
    enable = lib.mkEnableOption "Firefox Sync server secrets";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.ffsync_env = {
      sopsFile = ./ffsync_env.yaml;
    };
  };
}
