{
  services.linux-wallpaperengine = {
    enable = true;
    clamping = "clamp";
    assetsPath = "/home/taylor/.steam/steam/steamapps/common/wallpaper_engine/assets";
    wallpapers = [
      {
        monitor = "eDP-1";
        scaling = "fill";
        wallpaperId = "1132505365";
        fps = 30;
        audio = {
          silent = true;
        };
      }
    ];
  };
}
