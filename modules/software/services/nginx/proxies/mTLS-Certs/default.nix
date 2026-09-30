{ lib, ... }:

let
  # Public CA certs and CRLs, written by `mtls-ca` on build-nix. nginx reads
  # them as /etc/mTLSCerts/<name>.crt and <name>.crl.
  pemFiles = lib.filterAttrs (
    name: type: type == "regular" && (lib.hasSuffix ".crt" name || lib.hasSuffix ".crl" name)
  ) (builtins.readDir ./.);
in
{
  environment.etc = lib.mapAttrs' (
    name: _: lib.nameValuePair "mTLSCerts/${name}" { source = ./. + "/${name}"; }
  ) pemFiles;
}
