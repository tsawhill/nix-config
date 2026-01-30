{ lib, ... }:
{
  networking.firewall.allowedTCPPorts = [ 5335 ];
  networking.firewall.allowedUDPPorts = [ 5335 ];
  services.unbound = {
    enable = true;
    user = "root";
    group = "root";
    settings = {
      server = {
        do-ip6 = false;
        interface = [ "0.0.0.0" ];
        port = 5335;
        prefetch = true;
        username = lib.mkForce "root";

        harden-dnssec-stripped = true;
        cache-max-ttl = 86400;
        cache-min-ttl = 1200;
        cache-max-negative-ttl = 1;

        aggressive-nsec = true;
        hide-identity = true;
        hide-version = true;
        use-caps-for-id = true;
        qname-minimisation = true;
        private-address = [
          "192.168.0.0/16"
          "10.0.0.0/8"
        ];
        access-control = [
          "192.168.0.0/16 allow"
          "10.0.0.0/8 allow"
        ];
      };
      forward-zone = {
        name = "\".\"";
        forward-tls-upstream = true;
        forward-first = false;
        forward-addr = [
          "194.242.2.2@853#dns.mullvad.net" # Mullvad
          "9.9.9.9@853#dns.quad9.net" # Quad9
          "116.202.176.26@853#dot.libredns.gr" # Libredns
          "185.71.138.138@853#wikimedia-dns.org" # Wikimedia
          "84.200.69.80@853#resolver1.dns.watch" # dns.watch 1
          "84.200.70.40@853#resolver2.dns.watch" # dns.watch 2
          # "10.128.0.1@853#dns.airservers.org"
        ];
      };
    };
  };
}
