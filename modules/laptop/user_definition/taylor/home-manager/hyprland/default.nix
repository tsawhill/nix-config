{
  ...
}:
{
  imports = [
    ./monitors.nix
    # ./hyprpaper.nix
    # ./linux-wallpaperengine.nix
    ./mpvpaper.nix
  ];

  wayland.windowManager.hyprland.settings.device = {
    name = "pixa3854:00-093a:0274-touchpad";
    sensitivity = 0.8;
  };
}
