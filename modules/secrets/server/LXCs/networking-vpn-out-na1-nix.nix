{ config, lib, ... }:

let
  cfg = config.my.secrets."networking-vpn-out-na1-nix";
in
{
  options.my.secrets."networking-vpn-out-na1-nix".enable =
    lib.mkEnableOption "runtime secrets for the North American VPN egress gateway";

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      vpn_egress_wireguard_private_key = {
        sopsFile = ./networking-vpn-out-na1-nix.yaml;
        key = "wireguard_private_key";
      };
      vpn_egress_wireguard_preshared_key = {
        sopsFile = ./networking-vpn-out-na1-nix.yaml;
        key = "wireguard_preshared_key";
      };
      vpn_egress_gotify_token = {
        sopsFile = ./networking-vpn-out-na1-nix.yaml;
        key = "gotify_token";
      };
    };
  };
}
