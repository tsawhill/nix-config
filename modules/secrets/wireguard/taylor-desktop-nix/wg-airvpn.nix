{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.taylor-desktop-nix.wg-airvpn;
in
{
  options.my.secrets.wireguard.taylor-desktop-nix.wg-airvpn = {
    enable = lib.mkEnableOption "WireGuard private key for wg-airvpn on taylor-desktop-nix";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.wg_airvpn_private_key = {
      sopsFile = ./wg-airvpn.yaml;
      key = "private_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    sops.secrets.wg_airvpn_preshared_key = {
      sopsFile = ./wg-airvpn.yaml;
      key = "preshared_key";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
