{ config, lib, ... }:

let
  cfg = config.my.secrets.mtls-ca;
in
{
  options.my.secrets.mtls-ca = {
    enable = lib.mkEnableOption "the mTLS client CA's private key";
  };

  config = lib.mkIf cfg.enable {
    # Written once by `mtls-ca init` on build-nix; replacing it invalidates every client cert.
    sops.secrets.mtls_ca_key = {
      sopsFile = ./mtls-ca.yaml;
      key = "ca_key";
      owner = "mtls-ca";
      mode = "0400";
    };
  };
}
