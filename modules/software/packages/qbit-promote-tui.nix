{
  networkTopology,
  pkgs,
  ...
}:

let
  inherit (networkTopology.lib) fqdn;

  # The qBittorrent web UIs only accept whitelisted source addresses, and
  # build-nix is not one of them. arrs-nix is, and already carries qbit-promote,
  # so every API call is shelled through it rather than widening the whitelist.
  arrsHost = "root@${fqdn "arrs-nix"}";
  intake = "http://${fqdn "qbit-gen-nix"}:8080";
  seeding = "http://${fqdn "qbit-lts-nix"}:8080";

  # Categories the *arrs own. Those promote themselves on import, so listing
  # them here would only bury the ones that actually need a decision.
  autoCategories = [
    "tv-sonarr"
    "radarr"
    "lidarr"
  ];
  autoPattern = builtins.concatStringsSep "|" autoCategories;

  qbitPromoteTui = pkgs.writeShellScriptBin "qbit-promote-tui" ''
    set -euo pipefail

    GUM="${pkgs.gum}/bin/gum"
    JQ="${pkgs.jq}/bin/jq"
    SSH="${pkgs.openssh}/bin/ssh"

    ARRS="${arrsHost}"
    INTAKE="${intake}"
    SEEDING="${seeding}"

    # curl runs on arrs-nix; build-nix is not whitelisted on the web UIs.
    api() {
      $SSH -o ConnectTimeout=10 "$ARRS" "curl -s -m 60 $*"
    }

    echo "Fetching torrents from qbit-gen..."
    ALL=$(api "'$INTAKE/api/v2/torrents/info?filter=all'")

    # Each line is "<display>\t<hash>" so the hash survives selection without
    # having to match display text back to a torrent.
    ROWS=$(printf '%s' "$ALL" | $JQ -r '
      map(select(.category | test("^(${autoPattern})$") | not))
      | sort_by(-.added_on)
      | .[]
      | ((.size/1073741824*10|floor)/10|tostring) as $gb
      | ((.tracker // "") | capture("//(?<h>[^/:]+)").h) as $host
      | "\($gb)G\t\(.category // "-")\t\($host // "-")\t\(.name)\t\(.hash)"
      ' | awk -F"\t" "{printf \"%-8s %-9s %-20s %s\t%s\n\", \$1, \$2, \$3, substr(\$4,1,64), \$5}")

    if [ -z "$ROWS" ]; then
      echo "Nothing on qbit-gen to promote (excluding ${builtins.concatStringsSep ", " autoCategories})."
      exit 0
    fi

    echo
    SELECTED=$(printf '%s\n' "$ROWS" \
      | $GUM choose --no-limit --height 20 \
          --header "Select torrents to promote to qbit-lts  [size / category / tracker / name]") || exit 0

    if [ -z "$SELECTED" ]; then
      echo "Nothing selected."
      exit 0
    fi

    COUNT=$(printf '%s\n' "$SELECTED" | grep -c .)
    echo
    echo "Selected $COUNT torrent(s)."

    # auto leaves the tier to qbit-manage, which derives it from the tracker and
    # therefore matches that tracker's seeding rules. Forcing a shorter tier on a
    # tracker that wants longer is how hit-and-runs happen, so auto is default.
    TIER_CHOICE=$($GUM choose --header "Seeding tier" \
      "auto - qbit-manage decides from tracker (recommended)" \
      "t1 - force: seed forever" \
      "t2 - force: 30 days, then remove" \
      "t3 - force: 1 week or 1.0 ratio, then remove") || exit 0
    TIER=$(printf '%s' "$TIER_CHOICE" | ${pkgs.gawk}/bin/awk '{print $1}')

    if [ "$TIER" != "auto" ]; then
      $GUM confirm --default=No \
        "Force $TIER regardless of tracker? This can breach a tracker's seeding rules." || exit 0
    fi

    echo
    $GUM confirm "Promote $COUNT torrent(s) to qbit-lts as tier $TIER?" || exit 0
    echo

    OK=0
    FAILED=0
    while IFS=$'\t' read -r DISPLAY HASH; do
      if [ -z "''${HASH:-}" ]; then
        continue
      fi

      # Reuses the script the *arrs call on import: exports from intake, adds to
      # seeding at the identical save path with AutoTMM off, and only then
      # removes it from intake without its files. Any failure leaves it put.
      if $SSH -o ConnectTimeout=10 "$ARRS" \
           "Sonarr_EventType=Download Sonarr_Download_Id=$HASH qbit-promote" >/dev/null 2>&1; then
        if [ "$TIER" != "auto" ]; then
          # qbit-manage only tags untagged torrents, so this choice survives.
          api "-X POST '$SEEDING/api/v2/torrents/addTags' -d 'hashes=$HASH&tags=$TIER'" >/dev/null
        fi
        echo "  ok    $DISPLAY"
        OK=$((OK + 1))
      else
        echo "  FAIL  $DISPLAY"
        FAILED=$((FAILED + 1))
      fi
    done <<< "$SELECTED"

    echo
    echo "Promoted $OK, failed $FAILED."
    if [ "$FAILED" -gt 0 ]; then
      echo "Failures stayed on qbit-gen with their data intact."
    fi
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.jq
    qbitPromoteTui
  ];
}
