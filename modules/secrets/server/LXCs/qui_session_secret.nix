{ config, lib, ... }:

let
  cfg = config.my.secrets.qui_session_secret;
in
{
  options.my.secrets.qui_session_secret = {
    enable = lib.mkEnableOption "Secret for the qui session secret";
  };

  config = lib.mkIf cfg.enable {
    # Encrypts the stored qBittorrent credentials in qui's database, so rotating
    # this deregisters every instance. Treat it as permanent.
    sops.secrets.qui_session_secret = {
      sopsFile = ./qui_session_secret.yaml;
      key = "session_secret";
      mode = "0400";
      restartUnits = [ "qui.service" ];
    };
  };
}
