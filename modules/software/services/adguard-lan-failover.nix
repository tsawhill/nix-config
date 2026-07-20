{
  pkgs,
  lib,
  networkTopology,
  ...
}:

let
  inherit (networkTopology.lib) fqdn lanIp wgIp;

  # Hosts that roam between the LAN and the WireGuard remote-access network.
  # Their static AdGuard rewrite (see adguard.nix / topology `dnsAnswer`) is the
  # always-reachable WG IP; this reconciler upgrades that to the LAN IP whenever
  # the host is actually reachable on the LAN, so on-LAN clients get a direct
  # (non-tunnelled) connection. LAN wins when home, WG is the safe fallback.
  roaming = lib.filterAttrs (
    _: host: (host.dns.roaming or false) && (host.dns.enable or false)
  ) networkTopology.hosts;

  # One "<fqdn> <lanIp> <wgIp>" line per roaming host, consumed by the script.
  hostTable = pkgs.writeText "adguard-roaming-hosts" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: _: "${fqdn name} ${lanIp name} ${wgIp name}") roaming
    )
  );

  reconciler = pkgs.writeShellApplication {
    name = "adguard-lan-failover";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.iputils
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      api="http://127.0.0.1:80/control"

      # Fetch the current rewrites once. If AdGuard isn't up yet, skip quietly so
      # the timer just retries on the next tick instead of failing the unit.
      if ! rewrites="$(curl -fsS "$api/rewrite/list")"; then
        echo "adguard-lan-failover: AdGuard API unreachable, skipping this run"
        exit 0
      fi

      while read -r fqdn lan wg || [ -n "$fqdn" ]; do
        if [ -z "$fqdn" ]; then
          continue
        fi

        # No distinct LAN address to switch to; leave it alone.
        if [ "$lan" = "$wg" ]; then
          continue
        fi

        # The discriminator is pure LAN reachability: the WG tunnel is always up,
        # so only the LAN IP answering tells us the host is actually home.
        if ping -c2 -W1 "$lan" >/dev/null 2>&1; then
          desired="$lan"
        else
          desired="$wg"
        fi

        # Whatever AdGuard currently answers for this name.
        mapfile -t answers < <(
          printf '%s' "$rewrites" | jq -r --arg d "$fqdn" '.[] | select(.domain == $d) | .answer'
        )

        # Already exactly right: nothing to do.
        if [ "''${#answers[@]}" -eq 1 ] && [ "''${answers[0]}" = "$desired" ]; then
          continue
        fi

        # Drop any stale/duplicate answers for this name, then set the one we want.
        for a in "''${answers[@]}"; do
          curl -fsS -X POST "$api/rewrite/delete" \
            -H 'Content-Type: application/json' \
            -d "{\"domain\":\"$fqdn\",\"answer\":\"$a\"}" >/dev/null
        done

        curl -fsS -X POST "$api/rewrite/add" \
          -H 'Content-Type: application/json' \
          -d "{\"domain\":\"$fqdn\",\"answer\":\"$desired\"}" >/dev/null

        echo "adguard-lan-failover: $fqdn -> $desired"
      done < ${hostTable}
    '';
  };
in
{
  systemd.services.adguard-lan-failover = {
    description = "Point roaming .lan names at LAN IP when home, WG IP when away";
    after = [ "adguardhome.service" ];
    wants = [ "adguardhome.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${reconciler}/bin/adguard-lan-failover";
    };
  };

  systemd.timers.adguard-lan-failover = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "1m";
      Persistent = true;
    };
  };
}
