{ self, networkTopology, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/adguard.nix"
    "${self}/modules/software/services/adguard-lan-failover.nix"
    "${self}/modules/software/services/dns-recovery.nix"
  ];
  networking.hostName = "adguard-nix";
  my.services.dnsRecovery = {
    enable = true;
    service = "adguardhome";
    port = 53;
    upstreams = [
      [
        "@${networkTopology.lib.lanIp "unbound-vpn-na-nix"}"
        "-p"
        "5335"
      ]
    ];
  };

  /**
    Disable resolved DNS listener
    This occupies port 53 and does not allow adguard to use it
  */
  services.resolved.settings.Resolve.DNSStubListener = "no";
}
