{ config, lib, ... }:

let
  # A handy shorthand so we don't have to type the full path out every time
  cfg = config.my.secrets.prowlarr_api_key;
in
{

  options.my.secrets.prowlarr_api_key = {
    # lib.mkEnableOption automatically creates a boolean option that defaults to false.
    # The string provided is the description used if you ever generate man pages for your config.
    enable = lib.mkEnableOption "Secret for prowlarr API key";
  };

  # lib.mkIf ensures this entire block is ONLY evaluated if cfg.enable is set to true in a host's config.
  config = lib.mkIf cfg.enable {
    sops.secrets.prowlarr_api_key = {
      sopsFile = ./prowlarr_api_key.yaml;
    };
  };
}
