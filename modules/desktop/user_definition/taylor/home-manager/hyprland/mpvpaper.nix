{
  wayland.windowManager.hyprland.settings.exec-once = [
    # Wallpapers
    ''mpvpaper -o "no-audio --loop-playlist shuffle --loop-file=6" DP-4 /home/taylor/.config/wallpapers/2560x1440''
    ''mpvpaper -o "no-audio --loop-playlist shuffle --loop-file=6" DP-5 /home/taylor/.config/wallpapers/3440x1440''
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
