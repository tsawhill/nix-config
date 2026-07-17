{ config, lib, ... }:

let
  cfg = config.my.secrets.networkmanager.wifi.known-networks;

  defaultKeys = [
    "home_ssid"
    "home_psk"
    "parents_ssid"
    "parents_psk"
    "sisters_ssid"
    "sisters_psk"
  ];
in
{
  options.my.secrets.networkmanager.wifi.known-networks = {
    enable = lib.mkEnableOption "known Wi-Fi NetworkManager secrets";

    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultKeys;
      description = "Secret keys to load from known-networks.yaml.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs cfg.keys (key: {
      sopsFile = ./known-networks.yaml;
      inherit key;
      owner = "root";
      group = "root";
      mode = "0400";
    });
  };
}
