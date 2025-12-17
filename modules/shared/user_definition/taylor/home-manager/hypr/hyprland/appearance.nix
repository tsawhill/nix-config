{
  # Decoration settings
  wayland.windowManager.hyprland.settings.decoration = {
    rounding = 2;
    blur = {
      enabled = "true";
      size = 10;
    };
    shadow = {
      enabled = "true";
      range = 6;
      render_power = 2;
      color = "rgba(1a1a1aee)";
    };
  };

  # Animation settings
  wayland.windowManager.hyprland.settings.animations = {
    enabled = "true";
    bezier = [
      "linear, 0.5, 0.5, 0.5, 0.5"
      "myBezier, 0.05, 0.9, 0.1, 1.05"
    ];
    animation = [
      "windows, 1, 7, myBezier, popin 80%"
      "windowsOut, 1, 7, default, popin 80%"
      # "border, 1, 10, default"
      # "borderangle, 1, 50, linear, loop"
      "fade, 1, 7, default"
      "workspaces, 1, 6, default, slidefade 20%"
    ];
  };
  wayland.windowManager.hyprland.settings.general = {
    gaps_in = 8;
    gaps_out = 12;
    border_size = 4;
    # "col.active_border" = "rgba(ffcce6d9) rgba(9778D0FF) 45deg";
    # "col.inactive_border" = "rgba(595959aa)";
  };
}
