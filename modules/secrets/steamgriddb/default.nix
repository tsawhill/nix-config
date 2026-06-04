{ config, lib, ... }:

let
  cfg = config.my.secrets.steamgriddb_api_key;
in
{
  options.my.secrets.steamgriddb_api_key = {
    enable = lib.mkEnableOption "SteamGridDB API key (game box-art fetching)";
  };

  config = lib.mkIf cfg.enable {
    # Owned by taylor so the user-level `fetch-game-art` command can read it.
    sops.secrets.steamgriddb_api_key = {
      sopsFile = ./steamgriddb_api_key.yaml;
      owner = "taylor";
    };
  };
}
