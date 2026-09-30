{
  config,
  lib,
  pkgs,
  self,
  networkTopology,
  ...
}:

let
  cfg = config.my.network.wgRemoteServer;
  wgRemote = networkTopology.networks.wgRemote;
  lan = networkTopology.networks.lan;
  inherit (networkTopology.lib) lanIp wgIp;

  iface = "wg-remote";
  lanSuffix = ".${networkTopology.domains.lan}";
  prefix = lib.last (lib.splitString "/" wgRemote.cidr);
  confPath = config.sops.templates."wg-remote.conf".path;

  policy = import ./firewall/remote-access.nix;
  peers = policy.trusted ++ policy.restricted;
  peersWith = access: policy.${access};
  tunnelHosts = lib.attrNames (lib.filterAttrs (_: host: host ? wgRemote) networkTopology.hosts);
  pubkeySecret = name: "wg_pubkey_${lib.replaceStrings [ "-" ] [ "_" ] name}";

  # `proxy_pass` targets on *.lan hosts found in nginx config text.
  proxyTargets =
    protocol: text:
    let
      matches = lib.filter lib.isList (
        builtins.split "proxy_pass[[:space:]]+(https?://)?([A-Za-z0-9.-]+)(:([0-9]+))?" text
      );
      toTarget =
        match:
        let
          scheme = lib.elemAt match 0;
          host = lib.elemAt match 1;
          port = lib.elemAt match 3;
        in
        lib.optional (lib.hasSuffix lanSuffix host) {
          ip = lanIp (lib.removeSuffix lanSuffix host);
          inherit protocol;
          port =
            if port != null then
              lib.toInt port
            else if scheme == "https://" then
              443
            else
              80;
        };
    in
    lib.concatMap toTarget matches;

  httpTargets =
    nginx:
    lib.concatMap (
      vhost:
      proxyTargets "tcp" (
        lib.concatStringsSep "\n" (
          [ vhost.extraConfig ]
          ++ lib.concatMap (
            location:
            lib.optional (location.proxyPass != null) "proxy_pass ${location.proxyPass};"
            ++ [ location.extraConfig ]
          ) (lib.attrValues vhost.locations)
        )
      )
    ) (lib.attrValues nginx.virtualHosts);

  streamTargets =
    text:
    lib.concatMap (
      block:
      proxyTargets (
        if lib.length (builtins.split "listen[^;]*udp" block) > 1 then "udp" else "tcp"
      ) block
    ) (lib.filter lib.isString (builtins.split "server[[:space:]]*\\{" text));

  # A restricted peer may reach AdGuard plus whatever its own nginx proxies to.
  allowedTargets =
    name:
    let
      nginx = self.nixosConfigurations.${name}.config.services.nginx;
      dnsIp = lanIp lan.dnsHost;
    in
    [
      {
        ip = dnsIp;
        protocol = "udp";
        port = 53;
      }
      {
        ip = dnsIp;
        protocol = "tcp";
        port = 53;
      }
    ]
    ++ lib.optionals nginx.enable (httpTargets nginx ++ streamTargets nginx.streamConfig);

  restrictedElements = lib.unique (
    lib.concatMap (
      name:
      map (target: "${wgIp name} . ${target.ip} . ${target.protocol} . ${toString target.port}") (
        allowedTargets name
      )
    ) (peersWith "restricted")
  );
  trustedElements = map wgIp (peersWith "trusted");
in
{
  options.my.network.wgRemoteServer = {
    enable = lib.mkEnableOption "the WireGuard remote-access server with a two-tier forward firewall";

    upstreamInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
    };

    privateKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "wg_remote_server_private_key";
      description = "sops secret holding the server's private key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.sort lib.lessThan peers == lib.sort lib.lessThan tunnelHosts;
        message = "firewall/remote-access.nix must list every topology host with a wgRemote.ip exactly once (listed: ${toString peers}; topology: ${toString tunnelHosts}).";
      }
    ];

    my.secrets.wireguard.pubkeys.enable = true;

    sops.templates."wg-remote.conf" = {
      content =
        ''
          [Interface]
          PrivateKey = ${config.sops.placeholder.${cfg.privateKeySecret}}
          ListenPort = ${toString wgRemote.port}
        ''
        + lib.concatMapStrings (name: ''

          # ${name}
          [Peer]
          PublicKey = ${config.sops.placeholder.${pubkeySecret name}}
          AllowedIPs = ${wgIp name}/32
        '') peers;
      reloadUnits = [ "wg-remote.service" ];
    };

    systemd.services.wg-remote = {
      description = "WireGuard remote-access server";
      wantedBy = [ "multi-user.target" ];
      after = [ "nftables.service" ];
      requires = [ "nftables.service" ];
      path = [
        pkgs.iproute2
        pkgs.wireguard-tools
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # syncconf applies peer changes without dropping live sessions.
        ExecReload = "${pkgs.wireguard-tools}/bin/wg syncconf ${iface} ${confPath}";
      };
      script = ''
        ip link show ${iface} >/dev/null 2>&1 || ip link add ${iface} type wireguard
        wg syncconf ${iface} ${confPath}
        ip address replace ${wgRemote.routerAddress}/${prefix} dev ${iface}
        ip link set ${iface} up
      '';
      postStop = "ip link del ${iface} 2>/dev/null || true";
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
    };

    networking = {
      firewall.enable = false;
      nftables = {
        enable = true;
        tables.wg-remote = {
          family = "inet";
          content = ''
            set trusted {
              type ipv4_addr
              ${lib.optionalString (trustedElements != [ ]) "elements = { ${lib.concatStringsSep ", " trustedElements} }"}
            }

            # peer . destination . protocol . port
            set restricted {
              type ipv4_addr . ipv4_addr . inet_proto . inet_service
              ${lib.optionalString (restrictedElements != [ ]) "elements = { ${lib.concatStringsSep ", " restrictedElements} }"}
            }

            chain input {
              type filter hook input priority filter; policy drop;
              iifname "lo" accept
              ct state established,related accept
              ct state invalid drop
              ip protocol icmp accept
              iifname "${cfg.upstreamInterface}" udp dport ${toString wgRemote.port} accept
              iifname "${cfg.upstreamInterface}" ip saddr ${lan.cidr} tcp dport { 22, 9100, 9558 } accept
              iifname "${iface}" ip saddr @trusted tcp dport 22 accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
              ct state established,related accept
              ct state invalid drop
              iifname "${cfg.upstreamInterface}" oifname "${iface}" accept
              iifname "${iface}" ip saddr @trusted accept
              iifname "${iface}" ip saddr . ip daddr . meta l4proto . th dport @restricted accept
            }

            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              # Full-tunnel clients reach the internet through the LAN router.
              iifname "${iface}" oifname "${cfg.upstreamInterface}" ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } masquerade
            }
          '';
        };
      };
    };
  };
}
