{
  wayland.windowManager.hyprland.settings.exec-once = [
    # Wallpapers
    ''mpvpaper -o "no-audio --loop-playlist shuffle" DP-1 /home/taylor/.config/wallpapers/2560x1440''
    ''mpvpaper -o "no-audio --loop-playlist shuffle" DP-2 /home/taylor/.config/wallpapers/3440x1440''
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
