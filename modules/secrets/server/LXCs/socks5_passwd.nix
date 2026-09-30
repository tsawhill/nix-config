{ config, lib, ... }:

let
  cfg = config.my.secrets.socks5_passwd;
in
{
  options.my.secrets.socks5_passwd = {
    enable = lib.mkEnableOption "3proxy users file for the EU SOCKS5 proxy";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.socks5_passwd = {
      sopsFile = ./socks5_passwd.yaml;
    };
  };
}
