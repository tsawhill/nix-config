{ ... }:
{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "taylor";
    group = "users";
    key = "/etc/syncthing/key.pem";
    cert = "/etc/syncthing/cert.pem";
    settings = {
      options.relaysEnabled = false;
      optiosn.globalAnnounceEnabled = false;
      devices = {
        "thor".id = "UZKUGQ5-YZUACUX-UM7UKVH-ODTT5B3-4SSZUJ6-YI7H4XH-WZXSJMM-3AWQOA6";
        "server" = {
          id = "SCTSBHY-JM3BRIK-XOPRR5X-NJCFOT5-E2MUNII-WWEJYTV-FR2UUWG-76OAFAL";
          addresses = [ "tcp://syncthing-nix.lan:22000" ];
        };
      };
      folders = {
        "roms" = {
          path = "/home/taylor/Games/roms";
          devices = [
            "server"
            "thor"
          ];
        };
        "gamesaves" = {
          path = "/home/taylor/Games/saves";
          devices = [
            "server"
            "thor"
          ];
        };
      };
    };
  };
}
