{ config, lib, ... }:

let
  cfg = config.my.secrets."networking-router-nix";
in
{
  options.my.secrets."networking-router-nix".enable =
    lib.mkEnableOption "runtime secrets for the router";

  config = lib.mkIf cfg.enable {
    sops.secrets.router_switch_snmp = {
      sopsFile = ./networking-router-nix.yaml;
      key = "switch_snmp_conf";
    };
  };
}
