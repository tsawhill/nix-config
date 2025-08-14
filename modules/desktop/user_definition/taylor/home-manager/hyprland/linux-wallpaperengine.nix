{
  services.linux-wallpaperengine = {
    enable = true;
    # clamping = "clamp";
    # assetsPath = "/home/taylor/.steam/steam/steamapps/common/wallpaper_engine/assets";
    wallpapers = [
      {
        monitor = "DP-1";
        scaling = "fill";
        wallpaperId = "837766287";
        fps = 15;
        audio = {
          processing = false;
          silent = true;
        };
      }
      {
        monitor = "DP-2";
        scaling = "fill";
        wallpaperId = "1132505365";
        fps = 15;
        audio = {
          processing = false;
          silent = true;
        };
      }
      {
        monitor = "HDMI-A-1";
        scaling = "fill";
        wallpaperId = "1132505365";
        fps = 15;
        audio = {
          processing = false;
          silent = true;
        };
      }
    ];
  };
}
