{ ... }:
{
  programs.hyprpanel.layout = {
    "bar.layouts" = {
      "*" = {
        left = [
          "workspaces"
          "media"
        ];
        middle = [
          "windowtitle"
        ];
        right = [
          "volume"
          "microphone"
          "network"
          "bluetooth"
          "systray"
          "clock"
          "notifications"
          "dashboard"
        ];
      };
    };
  };
}
