{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.mtlsCa;
  stateDir = "/var/lib/mtls-ca";
  caCert = ./nginx/proxies/mTLS-Certs/mTLS-CA.crt;
  keyPath = "/run/secrets/mtls_ca_key";
  openssl = "${pkgs.openssl}/bin/openssl";

  opensslConfig = pkgs.writeText "mtls-ca.cnf" ''
    [ ca ]
    default_ca = mtls

    [ mtls ]
    dir = ${stateDir}
    database = $dir/index.txt
    new_certs_dir = $dir/certs
    crlnumber = $dir/crlnumber
    certificate = ${caCert}
    private_key = ${keyPath}
    rand_serial = yes
    unique_subject = no
    default_md = sha256
    default_days = 365
    # nginx rejects every client once a CRL's nextUpdate passes, so make it effectively permanent.
    default_crl_days = 3650
    policy = policy_cn
    copy_extensions = none
    x509_extensions = client_cert

    [ policy_cn ]
    commonName = supplied

    [ client_cert ]
    basicConstraints = critical, CA:FALSE
    keyUsage = critical, digitalSignature
    extendedKeyUsage = clientAuth
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid, issuer
  '';

  # Forced command for build-nix's key: sign a CSR, revoke a serial, or list the index.
  remote = pkgs.writeShellScript "mtls-ca-remote" ''
    set -euo pipefail
    umask 077
    cd ${stateDir}
    mkdir -p certs
    touch index.txt
    [ -s crlnumber ] || echo 1000 > crlnumber

    fail() { echo "mtls-ca: $*" >&2; exit 1; }
    [ -r ${keyPath} ] || fail "CA key not deployed; run mtls-ca init and enable the secret"

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    read -r action arg rest <<< "''${SSH_ORIGINAL_COMMAND:-}" || true
    [ -z "''${rest:-}" ] || fail "unexpected arguments"

    gencrl() {
      ${openssl} ca -config ${opensslConfig} -gencrl -out "$work/crl.pem" 2> "$work/log" \
        || { cat "$work/log" >&2; fail "CRL generation failed"; }
      cat "$work/crl.pem"
    }

    case "$action" in
      sign)
        [[ "$arg" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || fail "invalid name: $arg"
        head -c 16384 > "$work/req.csr"
        ${openssl} req -in "$work/req.csr" -noout -verify 2> /dev/null || fail "invalid CSR"
        ${openssl} ca -batch -notext -config ${opensslConfig} -in "$work/req.csr" \
          -subj "/CN=$arg" -out "$work/cert.pem" 2> "$work/log" \
          || { cat "$work/log" >&2; fail "signing failed"; }
        cat "$work/cert.pem"
        ;;
      revoke)
        [[ "$arg" =~ ^[0-9A-F]+$ ]] || fail "invalid serial: $arg"
        [ -f "certs/$arg.pem" ] || fail "no certificate with serial $arg"
        ${openssl} ca -batch -config ${opensslConfig} -revoke "certs/$arg.pem" 2> "$work/log" \
          || { cat "$work/log" >&2; fail "revocation failed"; }
        gencrl
        ;;
      crl)
        gencrl
        ;;
      list)
        cat index.txt
        ;;
      *)
        fail "usage: sign <name> | revoke <serial> | crl | list"
        ;;
    esac
  '';
in
{
  options.my.services.mtlsCa.enable = lib.mkEnableOption "the mTLS client certificate CA";

  config = lib.mkIf cfg.enable {
    users.groups.mtls-ca = { };
    users.users.mtls-ca = {
      isSystemUser = true;
      group = "mtls-ca";
      home = stateDir;
      # sshd needs a real shell to run the forced command.
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = [
        # build-nix's root key, limited to the CA commands
        ''restrict,command="${remote}" ${(import ../../ssh/access.nix).keys.build-nix-root}''
      ];
    };

    systemd.tmpfiles.rules = [ "d ${stateDir} 0700 mtls-ca mtls-ca -" ];
  };
}
