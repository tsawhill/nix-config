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
      devices."server" = {
        id = "JTHKLGM-CN3PZGC-ZZGSJMR-JERGJL3-NJ4JPW6-CRGEDFJ-MXA7D36-UT2SFQR";
        addresses = [ "tcp://syncthing-nix.lan:22000" ];
      };
      folders = {
        "roms" = {
          path = "/home/taylor/Games/roms";
          devices = [ "server" ];
        };
        "gamesaves" = {
          path = "/home/taylor/Games/saves";
          devices = [ "server" ];
        };
      };
    };
  };
}
