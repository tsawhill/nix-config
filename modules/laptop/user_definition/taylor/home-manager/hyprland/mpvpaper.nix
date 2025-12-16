{
  wayland.windowManager.hyprland.settings.exec-once = [
    # Wallpapers
    ''mpvpaper -o "no-audio --loop-playlist shuffle" eDP-1 /home/taylor/.config/wallpapers/2560x1440''
  ];
  programs.mpvpaper = {
    enable = true;
    pauseList = ''
      gamescope
      cs2
    '';
    stopList = ''
      gamescope
      cs2
    '';
  };
}
