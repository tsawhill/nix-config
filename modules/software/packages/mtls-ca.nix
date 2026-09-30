{
  networkTopology,
  pkgs,
  ...
}:

let
  mtlsCa = pkgs.writeShellScriptBin "mtls-ca" ''
    set -euo pipefail
    umask 077

    GUM="${pkgs.gum}/bin/gum"
    OPENSSL="${pkgs.openssl}/bin/openssl"
    SSH="${pkgs.openssh}/bin/ssh"
    SOPS="${pkgs.sops}/bin/sops"

    NIX_CONFIG="/mnt/zpool/code/nix-config"
    CERT_DIR="modules/software/services/nginx/proxies/mTLS-Certs"
    CA_CRT="$NIX_CONFIG/$CERT_DIR/mTLS-CA.crt"
    CA_CRL="$NIX_CONFIG/$CERT_DIR/mTLS-CA.crl"
    SECRET="modules/secrets/server/LXCs/mtls-ca.yaml"
    OUT_DIR="/root/mtls-out"
    CA_HOST="mtls-ca@${networkTopology.lib.fqdn "ca-nix"}"

    # Private keys only ever live here, on tmpfs, and are gone when the tool exits.
    WORK=$(mktemp -d -p /dev/shm mtls-ca.XXXXXX)
    trap 'rm -rf "$WORK"' EXIT

    remote() {
      "$SSH" -o BatchMode=yes -o ConnectTimeout=10 "$CA_HOST" "$@"
    }

    fail() {
      $GUM style --foreground 196 --bold "$*"
      exit 1
    }

    # index.txt: status, expiry (YYMMDDhhmmssZ), revoked at, serial, file, subject
    show_index() {
      soon=$(date -u -d "+30 days" +%y%m%d%H%M%S)
      now=$(date -u +%y%m%d%H%M%S)
      printf '%-24s %-10s %-12s %s\n' "NAME" "STATUS" "EXPIRES" "SERIAL"
      while IFS=$'\t' read -r status expiry _ serial _ subject; do
        name=''${subject##*CN=}
        stamp=''${expiry%Z}
        when="20''${stamp:0:2}-''${stamp:2:2}-''${stamp:4:2}"
        case "$status" in
          R) state="revoked" ;;
          *)
            if [[ "$stamp" < "$now" ]]; then state="expired"
            elif [[ "$stamp" < "$soon" ]]; then state="expiring"
            else state="valid"; fi
            ;;
        esac
        printf '%-24s %-10s %-12s %s\n' "$name" "$state" "$when" "$serial"
      done
    }

    do_init() {
      cd "$NIX_CONFIG"
      if [ -e "$SECRET" ]; then
        $GUM confirm --default=No \
          "A CA already exists. Replacing it invalidates every issued client cert. Continue?" \
          || exit 0
      fi

      CN=$($GUM input --value "tsawhill mTLS CA" --placeholder "CA common name")
      [ -n "$CN" ] || exit 1

      echo "==> Generating the CA key and certificate..."
      "$OPENSSL" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes \
        -keyout "$WORK/ca.key" -out "$WORK/ca.crt" -days 3650 -sha384 \
        -subj "/CN=$CN" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" 2> /dev/null

      echo "==> Encrypting the CA key into $SECRET..."
      { printf 'ca_key: |\n'; sed 's/^/  /' "$WORK/ca.key"; } \
        | "$SOPS" encrypt --filename-override "$SECRET" \
          --input-type yaml --output-type yaml --output "$WORK/secret.yaml" \
        || fail "sops encryption failed. Is the ca-nix creation rule in .sops.yaml?"
      mv "$WORK/secret.yaml" "$SECRET"
      chmod 644 "$SECRET"

      install -m 644 "$WORK/ca.crt" "$CA_CRT"
      rm -f "$CA_CRL"

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "CA created: $CN (valid 10 years)

    Next: set caEnabled = true in hosts/server-nix/LXCs/ca.nix,
    then deploy ca-nix and pi-backup-nix."
    }

    do_issue() {
      [ -r "$CA_CRT" ] || fail "No CA certificate at $CA_CRT"

      NAME=$($GUM input --placeholder "Device name (e.g. pixel7pro)")
      [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] \
        || fail "Use lowercase letters, digits and dashes."

      P12_PASS=$($GUM input --password --placeholder "Password for the .p12 file")
      [ -n "$P12_PASS" ] || fail "The .p12 needs a password."
      CONFIRM=$($GUM input --password --placeholder "Repeat the password")
      [ "$P12_PASS" = "$CONFIRM" ] || fail "Passwords don't match."
      export P12_PASS

      LEGACY=()
      if $GUM confirm --default=No "Use legacy .p12 encryption (older Android, iOS or macOS)?"; then
        LEGACY=(-legacy)
      fi

      echo "==> Generating the device key and CSR..."
      "$OPENSSL" req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$WORK/device.key" -out "$WORK/device.csr" -subj "/CN=$NAME" 2> /dev/null

      echo "==> Signing on ca-nix..."
      remote sign "$NAME" < "$WORK/device.csr" > "$WORK/device.crt" \
        || fail "ca-nix refused to sign."
      "$OPENSSL" verify -CAfile "$CA_CRT" "$WORK/device.crt" > /dev/null \
        || fail "The signed cert doesn't chain to $CA_CRT. Is ca-nix deployed with the current CA?"

      mkdir -p -m 700 "$OUT_DIR"
      "$OPENSSL" pkcs12 -export "''${LEGACY[@]}" \
        -inkey "$WORK/device.key" -in "$WORK/device.crt" -certfile "$CA_CRT" \
        -name "$NAME" -passout env:P12_PASS -out "$OUT_DIR/$NAME.p12"

      SERIAL=$("$OPENSSL" x509 -in "$WORK/device.crt" -noout -serial | cut -d= -f2)
      EXPIRES=$("$OPENSSL" x509 -in "$WORK/device.crt" -noout -enddate | cut -d= -f2)
      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Issued $NAME
    Serial:  $SERIAL
    Expires: $EXPIRES
    File:    $OUT_DIR/$NAME.p12

    Copy it to the device, import it, then delete it here."
    }

    do_list() {
      remote list > "$WORK/index.txt" || fail "Could not read the index from ca-nix."
      if [ ! -s "$WORK/index.txt" ]; then
        echo "No certificates issued yet."
        return
      fi
      show_index < "$WORK/index.txt"
    }

    do_revoke() {
      remote list > "$WORK/index.txt" || fail "Could not read the index from ca-nix."
      mapfile -t CHOICES < <(show_index < "$WORK/index.txt" | tail -n +2 | grep -v " revoked ")
      [ "''${#CHOICES[@]}" -gt 0 ] || fail "Nothing to revoke."

      $GUM style --foreground 212 "Select the certificate to revoke:"
      CHOICE=$($GUM choose "''${CHOICES[@]}")
      SERIAL=$(awk '{print $NF}' <<< "$CHOICE")
      $GUM confirm --default=No "Revoke $(awk '{print $1}' <<< "$CHOICE") ($SERIAL)?" || exit 0

      remote revoke "$SERIAL" > "$WORK/crl.pem" || fail "ca-nix could not revoke $SERIAL."
      "$OPENSSL" crl -in "$WORK/crl.pem" -noout -CAfile "$CA_CRT" 2> /dev/null \
        || fail "ca-nix returned an invalid CRL."
      install -m 644 "$WORK/crl.pem" "$CA_CRL"

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Revoked $SERIAL and updated $CERT_DIR/mTLS-CA.crl

    Deploy pi-backup-nix for nginx to start rejecting it."
    }

    ACTION=''${1:-$($GUM choose "issue" "list" "revoke" "init")}
    case "$ACTION" in
      issue) do_issue ;;
      list) do_list ;;
      revoke) do_revoke ;;
      init) do_init ;;
      *) fail "usage: mtls-ca [issue|list|revoke|init]" ;;
    esac
  '';
in
{
  environment.systemPackages = [ mtlsCa ];
}
