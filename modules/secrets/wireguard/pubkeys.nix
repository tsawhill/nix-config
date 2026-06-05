{ config, lib, ... }:

let
  cfg = config.my.secrets.wireguard.pubkeys;

  sopsFile = ./pubkeys.yaml;

  keys = {
    wg_pubkey_router_wg_remote = "router_wg_remote";
    wg_pubkey_oracle_rocky_proxy = "oracle_rocky_proxy";
    wg_pubkey_pixel7pro = "pixel7pro";
    wg_pubkey_fwlaptop = "fwlaptop";
    wg_pubkey_pi_backup_nix = "pi_backup_nix";
    wg_pubkey_taylor_desktop_nix = "taylor_desktop_nix";
    wg_pubkey_taylor_laptop_nix = "taylor_laptop_nix";
    wg_pubkey_taylor_deck_nix = "taylor_deck_nix";
    wg_pubkey_airvpn = "airvpn";
  };
in
{
  options.my.secrets.wireguard.pubkeys = {
    enable = lib.mkEnableOption "shared WireGuard public keys";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.mapAttrs (_name: yamlKey: {
      inherit sopsFile;
      key = yamlKey;
      owner = "root";
      group = "root";
      mode = "0444";
    }) keys;
  };
}
