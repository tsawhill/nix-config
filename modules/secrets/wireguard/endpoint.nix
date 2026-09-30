{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.endpoint;
in
{
  options.my.secrets.wireguard.endpoint = {
    enable = lib.mkEnableOption "the DNS name of the home WireGuard endpoint";
  };

  config = lib.mkIf cfg.enable {
    # A hostname only, no port. Secret because the repo is public and it resolves to the home WAN.
    sops.secrets.wg_remote_endpoint = {
      sopsFile = ./endpoint.yaml;
      key = "endpoint";
      mode = "0400";
    };
  };
}
