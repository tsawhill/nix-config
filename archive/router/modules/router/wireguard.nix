{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.router;

  inherit (lib)
    concatStringsSep
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkIf
    nameValuePair
    optional
    optionalAttrs
    ;

  # ── Server helpers ───────────────────────────────────────────────────

  mkServerNetdev = name: server: {
    netdevConfig = {
      Name = name;
      Kind = "wireguard";
      MTUBytes = toString (if server.mtu != null then server.mtu else 1420);
    };
    wireguardConfig = {
      PrivateKeyFile = server.privateKeyFile;
      ListenPort = server.listenPort;
    };
    wireguardPeers = map (peer:
      {
        AllowedIPs = peer.allowedIPs;
      }
      // optionalAttrs (peer.publicKey != null) { PublicKey = peer.publicKey; }
      // optionalAttrs (peer.publicKeyFile != null) { PublicKeyFile = peer.publicKeyFile; }
      // optionalAttrs (peer.endpoint != null) { Endpoint = peer.endpoint; }
      // optionalAttrs (peer.persistentKeepalive != null) {
        PersistentKeepalive = peer.persistentKeepalive;
      }
      // optionalAttrs (peer.presharedKeyFile != null) {
        PresharedKeyFile = peer.presharedKeyFile;
      }
      // optionalAttrs (peer.name != null) { Name = peer.name; }
    ) server.peers;
  };

  mkServerNetwork = name: server: {
    matchConfig.Name = name;
    address = [ server.address ];
    networkConfig = {
      IPv4Forwarding = true;
    };
  };

  # ── Client helpers ───────────────────────────────────────────────────

  mkClientNetdev = name: client: {
    netdevConfig = {
      Name = name;
      Kind = "wireguard";
      MTUBytes = toString (if client.mtu != null then client.mtu else 1420);
    };
    wireguardConfig = {
      PrivateKeyFile = client.privateKeyFile;
    } // optionalAttrs (client.fwMark != null) {
      FirewallMark = client.fwMark;
    };
    wireguardPeers = [
      ({
        AllowedIPs = client.allowedIPs;
      }
      // optionalAttrs (client.publicKey != null) { PublicKey = client.publicKey; }
      // optionalAttrs (client.publicKeyFile != null) { PublicKeyFile = client.publicKeyFile; }
      // optionalAttrs (client.endpoint != null) { Endpoint = client.endpoint; }
      // optionalAttrs (client.persistentKeepalive != null) {
        PersistentKeepalive = client.persistentKeepalive;
      }
      // optionalAttrs (client.presharedKeyFile != null) {
        PresharedKeyFile = client.presharedKeyFile;
      })
    ];
  };

  mkClientNetwork = name: client: {
    matchConfig.Name = name;
    address = [ client.address ];
    networkConfig = {
      IPv4Forwarding = true;
    };
    routes = optional (client.allowedIPs != [ "0.0.0.0/0" ]) {
      Destination = builtins.head client.allowedIPs;
    };
  };

  # ── Policy routing ───────────────────────────────────────────────────

  routedWireguardClients = filterAttrs (
    _name: client: client.gateway != null && client.routeTable != null && client.fwMark != null
  ) cfg.wireguard.clients;

  policyRouteSetup = concatStringsSep "\n" (
    mapAttrsToList (
      name: client:
      ''
        until ${pkgs.iproute2}/bin/ip link show ${name} >/dev/null 2>&1; do
          sleep 1
        done
        ${pkgs.iproute2}/bin/ip route replace default via ${client.gateway} dev ${name} table ${toString client.routeTable}
        ${pkgs.iproute2}/bin/ip rule add fwmark ${toString client.fwMark} table ${toString client.routeTable} priority ${toString client.routePriority} 2>/dev/null || true
      ''
    ) routedWireguardClients
  );

  policyRouteCleanup = concatStringsSep "\n" (
    mapAttrsToList (
      _name: client:
      ''
        ${pkgs.iproute2}/bin/ip rule del fwmark ${toString client.fwMark} table ${toString client.routeTable} priority ${toString client.routePriority} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip route del default table ${toString client.routeTable} 2>/dev/null || true
      ''
    ) routedWireguardClients
  );
in
{
  config = mkIf cfg.enable {
    systemd.network.netdevs =
      (mapAttrs' (name: server: nameValuePair "50-${name}" (mkServerNetdev name server)) cfg.wireguard.servers)
      // (mapAttrs' (name: client: nameValuePair "50-${name}" (mkClientNetdev name client)) cfg.wireguard.clients);

    systemd.network.networks =
      (mapAttrs' (name: server: nameValuePair "50-${name}" (mkServerNetwork name server)) cfg.wireguard.servers)
      // (mapAttrs' (name: client: nameValuePair "50-${name}" (mkClientNetwork name client)) cfg.wireguard.clients);

    systemd.services.router-wireguard-policy-routes = mkIf (routedWireguardClients != { }) {
      description = "Router WireGuard policy routing tables";
      after = [
        "systemd-networkd.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = policyRouteSetup;
      postStop = policyRouteCleanup;
    };
  };
}
