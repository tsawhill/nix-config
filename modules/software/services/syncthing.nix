{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    settings = {
      options.relaysEnabled = false;
      devices = {
        "thor".id = "UZKUGQ5-YZUACUX-UM7UKVH-ODTT5B3-4SSZUJ6-YI7H4XH-WZXSJMM-3AWQOA6";
        "desktop" = {
          id = "2YOU7Q7-JQWSJZT-52R5W4D-E35IIEW-QAQUH6W-D22RGN6-365VAED-WIJBNAT";
          addresses = [ "tcp://desktop-nix.lan:22000" ];
        };
      };
      folders = {
        "roms" = {
          path = "/mnt/zpool/roms";
          devices = [
            "thor"
            "desktop"
          ];
        };
        "gamesaves" = {
          path = "/mnt/zpool/gamesaves";
          devices = [
            "thor"
            "desktop"
          ];
        };
      };
    };
  };
}
