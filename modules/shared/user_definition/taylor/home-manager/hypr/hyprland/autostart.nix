{
  wayland.windowManager.hyprland.settings.exec-once = [
    "hyprpanel"
    "hyprpolkitagent"
    "MANGOHUD=0 walker --gapplication-service"
    "xrandr --output DP-1 --primary"

    "easyeffects --gapplication-service"
    "openrgb --startminimized --noautoconnect -p default"

    "steam"
    "sleep 15; heroic"
    "sleep 10; vesktop"
    "feishin"

    # Wallpapers
    ''mpvpaper -o "no-audio --loop-playlist shuffle --ab-loop-a=00:05 --ab-loop-b=5" DP-1 /home/taylor/.config/wallpapers/2560x1440''

    # Bluetooth does not consistently start on boot because the device is not detected until after networking starts.
    "rfkill unblock 0;sleep 15; rfkill unblock 0"
  ];
}
