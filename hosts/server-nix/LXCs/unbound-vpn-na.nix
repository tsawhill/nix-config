{
  networkTopology,
  self,
  ...
}:
{
  imports = [
    ./base
    "${self}/modules/network/vpn-egress-client.nix"
    "${self}/modules/software/services/unbound.nix"
    "${self}/modules/software/services/dns-recovery.nix"
  ];
  networking.hostName = "unbound-vpn-na-nix";

  my.services.dnsRecovery = {
    enable = true;
    service = "unbound";
    port = 5335;
    upstreams = [
      [
        "@9.9.9.9"
        "+tls-ca=/etc/ssl/certs/ca-certificates.crt"
        "+tls-hostname=dns.quad9.net"
      ]
      [
        "@194.242.2.2"
        "+tls-ca=/etc/ssl/certs/ca-certificates.crt"
        "+tls-hostname=dns.mullvad.net"
      ]
    ];
  };
  # Retry upstreams promptly after tunnel recovery instead of remembering
  # their outage for the default fifteen-minute infrastructure-cache TTL.
  services.unbound.settings.server.infra-host-ttl = 60;

  my.network.vpnEgress.client = {
    enable = true;
    gatewayAddress = networkTopology.lib.lanIp "networking-vpn-out-na1-nix";
    normalGateway = networkTopology.networks.lan.gateway;
    bypassCidrs = [ networkTopology.networks.wgRemote.routedCidr ];
  };
}
