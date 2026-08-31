{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.network.airvpn;

  endpointsJson = pkgs.writeText "airvpn-switch-endpoints.json" (builtins.toJSON cfg.endpoints);

  # Empty on hosts without a vpn-egress gateway, which switch directly with nmcli.
  controllerArgs = lib.optionalString (
    cfg.switchTool.controllerCommand != null
  ) cfg.switchTool.controllerCommand;

  airvpnSwitchScript = pkgs.writeShellScriptBin "airvpn-switch" ''
    set -euo pipefail

    # --- Tool paths (pinned to nix store) ---
    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    JQ="${pkgs.jq}/bin/jq"
    WG="${pkgs.wireguard-tools}/bin/wg"
    NMCLI="${pkgs.networkmanager}/bin/nmcli"
    CURL="${pkgs.curl}/bin/curl"

    ENDPOINTS="${endpointsJson}"
    INTERFACE="${cfg.interfaceName}"
    TUNNEL_IP="${lib.head (lib.splitString "/" cfg.address)}"
    PUBLIC_IP_URL="${cfg.switchTool.publicIpUrl}"
    PROBE_TIMEOUT=${toString cfg.switchTool.probeTimeoutSeconds}

    # On a gateway the egress controller owns rotation state and the rotation
    # lock, so a manual switch has to go through it or the next health check
    # and the next boot would disagree with the operator's choice.
    CONTROLLER=(${controllerArgs})

    die() {
      $GUM style --foreground 196 --bold "$1"
      exit 1
    }

    require_root() {
      if [ "$(id -u)" -ne 0 ]; then
        die "airvpn-switch needs root (try: sudo airvpn-switch)."
      fi
    }

    endpoint_field() {
      $JQ -r --arg name "$1" --arg field "$2" \
        'map(select(.name == $name)) | .[0][$field] // empty' "$ENDPOINTS"
    }

    active_connection_id() {
      $NMCLI --terse --fields NAME,DEVICE connection show --active 2>/dev/null |
        while IFS=: read -r name device; do
          if [ "$device" = "$INTERFACE" ]; then
            printf '%s\n' "$name"
          fi
        done || true
    }

    current_endpoint() {
      local id
      id=$(active_connection_id)
      if [ -n "$id" ]; then
        $JQ -r --arg id "$id" \
          'map(select(.connectionId == $id)) | .[0].name // empty' "$ENDPOINTS"
      fi
    }

    handshake_stamp() {
      local newest=0 stamp
      while read -r stamp; do
        if [ -n "$stamp" ] && [ "$stamp" -gt "$newest" ]; then
          newest=$stamp
        fi
      done < <($WG show "$INTERFACE" latest-handshakes 2>/dev/null | cut -f2)
      printf '%s\n' "$newest"
    }

    handshake_age() {
      local stamp
      stamp=$(handshake_stamp)
      if [ "$stamp" -eq 0 ]; then
        printf 'never\n'
      else
        printf '%ss ago\n' "$(( $(date +%s) - stamp ))"
      fi
    }

    public_ip() {
      $CURL --fail --silent --show-error --max-time "$PROBE_TIMEOUT" \
        --interface "$TUNNEL_IP" "$PUBLIC_IP_URL" 2>/dev/null || true
    }

    # A profile is only considered up once the peer has handshaked and traffic
    # actually leaves through the tunnel address.
    verify_tunnel() {
      local waited=0 probes=0
      while [ "$waited" -lt "$PROBE_TIMEOUT" ]; do
        if [ "$(handshake_stamp)" -ne 0 ]; then
          if [ -n "$(public_ip)" ]; then
            return 0
          fi
          # Each probe already costs up to PROBE_TIMEOUT, so allow one retry.
          probes=$((probes + 1))
          if [ "$probes" -ge 2 ]; then
            return 1
          fi
        fi
        sleep 1
        waited=$((waited + 1))
      done
      return 1
    }

    show_status() {
      local name exit_ip
      name=$(current_endpoint)

      $GUM style --foreground 86 --bold "Current tunnel:"
      if [ -z "$name" ]; then
        echo "  Endpoint:  none active on $INTERFACE"
      else
        echo "  Endpoint:  $name ($(endpoint_field "$name" country) / $(endpoint_field "$name" city))"
        echo "  Peer:      $(endpoint_field "$name" ip):$(endpoint_field "$name" port)"
      fi
      echo "  Interface: $INTERFACE ($TUNNEL_IP)"
      echo "  Handshake: $(handshake_age)"
      exit_ip=$(public_ip)
      echo "  Exit IP:   ''${exit_ip:-unreachable}"
      if [ "''${#CONTROLLER[@]}" -gt 0 ]; then
        echo "  Managed:   vpn-egress controller"
      else
        echo "  Managed:   NetworkManager"
      fi
    }

    connect_endpoint() {
      local name="$1" id previous output
      id=$(endpoint_field "$name" connectionId)
      if [ -z "$id" ]; then
        $GUM style --foreground 196 --bold "Unknown endpoint: $name"
        return 1
      fi

      echo ""
      $GUM style --foreground 212 "Activating $name ($id)..."

      if [ "''${#CONTROLLER[@]}" -gt 0 ]; then
        if ! output=$("''${CONTROLLER[@]}" switch --endpoint "$name" 2>&1); then
          $GUM style --foreground 196 --bold "Switch to $name failed."
          echo "  $output"
          return 1
        fi
        $GUM style --foreground 82 --border rounded --padding "1 2" \
          "Connected to $name ($(printf '%s' "$output" | $JQ -r '.publicIp'))"
        if [ "$(printf '%s' "$output" | $JQ -r '.blockedExit')" = "true" ]; then
          $GUM style --foreground 214 \
            "Note: this exit IP is on the blocked list; automatic rotation may move off it."
        fi
        return 0
      fi

      previous=$(current_endpoint)
      if ! $NMCLI --wait "$PROBE_TIMEOUT" connection up id "$id" >/dev/null 2>&1; then
        $GUM style --foreground 196 --bold "NetworkManager could not activate $id."
        return 1
      fi

      if ! verify_tunnel; then
        $GUM style --foreground 196 --bold "$name did not pass its handshake and exit-IP check."
        if [ -n "$previous" ] && [ "$previous" != "$name" ]; then
          $GUM style --foreground 214 "Restoring $previous..."
          $NMCLI --wait "$PROBE_TIMEOUT" connection up id \
            "$(endpoint_field "$previous" connectionId)" >/dev/null 2>&1 || true
        fi
        return 1
      fi

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Connected to $name ($(public_ip))"
    }

    do_switch() {
      local current selection name
      current=$(current_endpoint)

      echo ""
      $GUM style --foreground 212 "Select an AirVPN server:"

      # pad falls back to a single space so a long name can never run into the
      # next column and break the field split below.
      selection=$($JQ -r --arg current "$current" '
          def pad($n): . + ((" " * ($n - length)) // " ");
          sort_by(.country, .city, .name)[]
          | (if .name == $current then "* " else "  " end)
            + (.name | pad(16))
            + (.country | pad(4))
            + (.city | pad(24))
            + .ip
        ' "$ENDPOINTS" |
        $GUM filter --height 20 --placeholder "Search by server, country, or city") || return 0

      selection="''${selection:2}"
      name="''${selection%% *}"
      if [ -z "$name" ]; then
        return 0
      fi
      connect_endpoint "$name" || true
    }

    do_random() {
      local current name
      current=$(current_endpoint)
      name=$($JQ -r --arg current "$current" \
        'map(select(.name != $current))[].name' "$ENDPOINTS" | shuf -n 1)
      if [ -z "$name" ]; then
        $GUM style --foreground 214 "No other server is available in this selection."
        return 0
      fi
      connect_endpoint "$name" || true
    }

    do_reconnect() {
      local current
      current=$(current_endpoint)
      if [ -z "$current" ]; then
        $GUM style --foreground 214 "Nothing is active; pick a server with \"switch\" first."
        return 0
      fi
      connect_endpoint "$current" || true
    }

    pause() {
      echo ""
      read -r -p "Press enter to continue... " _ || true
    }

    require_root

    while true; do
      clear
      $GUM style --foreground 86 --border-foreground 86 --border double \
        --align center --width 50 "$($FIGLET -f small "AIRVPN SWITCH")"

      show_status
      echo ""

      $GUM style --foreground 212 "Action:"
      ACTION=$($GUM choose "switch" "random" "reconnect" "refresh" "quit") || exit 0

      case "$ACTION" in
        switch)
          do_switch
          pause
          ;;
        random)
          do_random
          pause
          ;;
        reconnect)
          do_reconnect
          pause
          ;;
        refresh) ;;
        *) exit 0 ;;
      esac
    done
  '';
in
{
  options.my.network.airvpn.switchTool = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.switchTool.controllerCommand != null;
      description = "Install the interactive airvpn-switch endpoint picker. Defaults to gateway hosts, which are the ones reached over SSH.";
    };

    controllerCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "vpn-egress controller invocation used to keep manual switches in sync with rotation state.";
    };

    publicIpUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.ipify.org";
      description = "Endpoint queried through the tunnel to display the current exit IP.";
    };

    probeTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds allowed for profile activation, handshake, and exit-IP probes.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.switchTool.enable) {
    environment.systemPackages = [
      pkgs.gum
      pkgs.figlet
      pkgs.jq
      airvpnSwitchScript
    ];
  };
}
