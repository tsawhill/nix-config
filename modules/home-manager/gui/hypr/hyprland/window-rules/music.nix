{ ... }:
{
  wayland.windowManager.hyprland.settings.window_rule = [
    {
      match.class = "feishin";
      float = true;
      size = "(monitor_w*0.7) (monitor_h*0.8)";
      center = true;
    }
  ];
}
