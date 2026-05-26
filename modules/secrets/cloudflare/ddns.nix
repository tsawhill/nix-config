{ config, lib, ... }:

let
  cfg = config.my.secrets.cloudflare.ddns;
in
{
  options.my.secrets.cloudflare.ddns = {
    enable = lib.mkEnableOption "Cloudflare API token for dynamic DNS updates";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.cloudflare_ddns_api_token = {
      sopsFile = ./ddns.yaml;
      key = "api_token";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
