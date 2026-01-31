{ lib, ... }:

{
  options = {
    enable = lib.mkEnableOption "Enable Proxy";

    mTLSCert = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "mTLS-CA";
      description = "The name of the CA certificate (stored in /etc/Certs/) to use for mTLS. If null, mTLS is disabled.";
    };

    enableAuthentik = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hostname for authentik authentication. If not specified, authentik is disabled";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for this reverse proxy";
    };

    restrictToIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Restrict access to the IPs given for this option";
    };
  };
}
