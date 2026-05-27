{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.router;

  inherit (lib)
    filterAttrs
    mapAttrs'
    mkIf
    nameValuePair
    optionalAttrs
    ;

  mkPeer =
    peer:
    {
      publicKey = peer.publicKey;
      allowedIPs = peer.allowedIPs;
    }
    // optionalAttrs (peer.name != null) { name = peer.name; }
    // optionalAttrs (peer.endpoint != null) { endpoint = peer.endpoint; }
    // optionalAttrs (peer.persistentKeepalive != null) {
      persistentKeepalive = peer.persistentKeepalive;
    }
    // optionalAttrs (peer.presharedKeyFile != null) {
      presharedKeyFile = peer.presharedKeyFile;
    };

  mkServer = _name: server: {
    ips = [ server.address ];
    listenPort = server.listenPort;
    privateKeyFile = server.privateKeyFile;
    peers = map mkPeer server.peers;
  } // optionalAttrs (server.mtu != null) { mtu = server.mtu; };

  # Client/provider tunnels do not install 0.0.0.0/0 automatically. Policy
  # routing below decides which marked flows use which provider table.
  mkClient =
    name: client:
    {
      ips = [ client.address ];
      privateKeyFile = client.privateKeyFile;
      allowedIPsAsRoutes = false;
      peers = [
        (mkPeer {
          inherit (client)
            publicKey
            allowedIPs
            endpoint
            persistentKeepalive
            presharedKeyFile
            ;
          name = name;
        })
      ];
    }
    // optionalAttrs (client.mtu != null) { mtu = client.mtu; }
    // optionalAttrs (client.fwMark != null) { fwMark = toString client.fwMark; };

  routedWireguardClients = filterAttrs (
    _name: client: client.gateway != null && client.routeTable != null && client.fwMark != null
  ) cfg.wireguard.clients;

  policyRouteSetup = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
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

  policyRouteCleanup = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
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
    networking.wireguard.interfaces =
      (mapAttrs' (name: server: nameValuePair name (mkServer name server)) cfg.wireguard.servers)
      // (mapAttrs' (name: client: nameValuePair name (mkClient name client)) cfg.wireguard.clients);

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
