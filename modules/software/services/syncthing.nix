{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    settings = {
      devices = {
        "thor".id = "UZKUGQ5-YZUACUX-UM7UKVH-ODTT5B3-4SSZUJ6-YI7H4XH-WZXSJMM-3AWQOA6";
        "desktop".id = "MLCVIC4-4F7UHHD-2KWDPRW-GS53XUX-XERXG3N-4X37IKX-6A6A5I2-Q6QERAW";
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
