{ pkgs, ... }:
{
  # Decoration settings
  wayland.windowManager.hyprland.settings.decoration = {
    rounding = 0;
    blur = {
      enabled = "true";
      size = 6;
      passes = 3; # Multiple passes create a much smoother, frosted glass look
      ignore_opacity = true; # Ensures blur works nicely with window transparency
    };
    shadow = {
      enabled = "true";
      range = 20; # Increased range for a wider glow
      render_power = 3; # Softer falloff
      color = "rgba(00000066)"; # Darker, more transparent shadow for better contrast
    };
  };

  # Animation settings
  wayland.windowManager.hyprland.settings.animations = {
    enabled = "true";
    bezier = [
      "linear, 0.5, 0.5, 0.5, 0.5"
      "overshoot, 0.05, 0.9, 0.1, 1.1"
      "goofy, 0.2, 1.6, 0.4, 1.5" # Fast fly-in, snappier snap-back
    ];
    animation = [
      "windows, 1, 6, goofy, popin"
      "windowsOut, 1, 5, goofy, popin"
      "fade, 1, 5, default"
      "workspaces, 1, 6, default, slidefade 20%"
    ];
  };

  wayland.windowManager.hyprland.settings.general = {
    gaps_in = 4;
    gaps_out = 12;
    border_size = 3;
    "col.active_border" = "rgba(ffcce6ff) rgba(9778D0ff) 45deg";
    "col.inactive_border" = "rgba(595959aa)";
  };

  # Cursor
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.catppuccin-cursors.mochaPink;
    name = "catppuccin-mocha-pink-cursors";
    size = 16;
  };
  wayland.windowManager.hyprland.settings.env = [
    "HYPRCURSOR_THEME,catppuccin-mocha-pink-cursors"
    "HYPRCURSOR_SIZE,16"
    "XCURSOR_THEME,catppuccin-mocha-pink-cursors"
    "XCURSOR_SIZE,16"
  ];
  # Disable hardware cursors to fix Hyprland 0.54 rendering bugs
  wayland.windowManager.hyprland.settings.cursor = {
    no_hardware_cursors = true;
  };
}
