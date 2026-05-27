{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.router-nix;
in
{
  options.my.secrets.wireguard.router-nix = {
    enable = lib.mkEnableOption "WireGuard keys for router-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.router_wg_remote_private_key = {
      sopsFile = ./router-nix.yaml;
      key = "remote_private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.router_wg_airvpn_ch_private_key = {
      sopsFile = ./router-nix.yaml;
      key = "airvpn_ch_private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.router_wg_airvpn_ch_preshared_key = {
      sopsFile = ./router-nix.yaml;
      key = "airvpn_ch_preshared_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.router_wg_airvpn_na_private_key = {
      sopsFile = ./router-nix.yaml;
      key = "airvpn_na_private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.router_wg_airvpn_na_preshared_key = {
      sopsFile = ./router-nix.yaml;
      key = "airvpn_na_preshared_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
