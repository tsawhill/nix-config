{ networkTopology, ... }:
{
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "sambanix";
        "netbios name" = "sambanix";
        "security" = "user";

        # IPv4 only
        "interfaces" = "eth0";
        "bind interfaces only" = "yes";

        "hosts allow" =
          "${networkTopology.networks.lan.cidr} ${networkTopology.networks.wgRemote.cidr} localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
    };
  };
}
