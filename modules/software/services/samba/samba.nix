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

        "hosts allow" = "10.73.73.0/24 10.50.50.0/24 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
    };
  };
}
