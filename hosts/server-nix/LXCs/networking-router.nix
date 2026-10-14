{
  config,
  self,
  ...
}:

{
  imports = [
    ./base
    "${self}/modules/network/router.nix"
  ];

  networking.hostName = "networking-router-nix";

  my.secrets."networking-router-nix".enable = true;

  my.network.router = {
    enable = true;
    # Took over from OPNsense on 2026-09-30.
    takeover = true;
    # OPNsense's old wan0 MAC, so the ISP lease carried over
    wanMacAddress = "14:29:0d:71:37:01";
    portShaping = {
      enable = true;
      snmpConfigFile = config.sops.secrets.router_switch_snmp.path;
    };
    # Plan is 2300 down / 357 up.
    wanQos = {
      enable = true;
      downloadMbit = 2150;
      uploadMbit = 340;
      priorityHosts = [
        "taylor-desktop-nix"
        "taylor-laptop-nix"
        "taylor-cube-nix"
        "taylor-deck-nix"
      ];
    };
  };
}
