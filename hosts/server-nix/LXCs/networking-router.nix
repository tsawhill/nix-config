{
  self,
  ...
}:

{
  imports = [
    ./base
    "${self}/modules/network/router.nix"
  ];

  networking.hostName = "networking-router-nix";

  my.network.router = {
    enable = true;
    # Took over from OPNsense on 2026-09-30.
    takeover = true;
    # OPNsense's old wan0 MAC, so the ISP lease carried over
    wanMacAddress = "14:29:0d:71:37:01";
  };
}
