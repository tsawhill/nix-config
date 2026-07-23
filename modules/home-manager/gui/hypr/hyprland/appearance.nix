{ pkgs, ... }:
{
  # Decoration settings -> hl.config({ decoration = { ... } })
  wayland.windowManager.hyprland.settings.config.decoration = {
    rounding = 0;
    blur = {
      enabled = true;
      size = 6;
      passes = 3; # Multiple passes create a much smoother, frosted glass look
      ignore_opacity = false; # Ensures blur works nicely with window transparency
    };
    shadow = {
      enabled = true;
      range = 20; # Increased range for a wider glow
      render_power = 3; # Softer falloff
      color = "rgba(00000066)"; # Darker, more transparent shadow for better contrast
    };
  };

  # Only the enable flag is a config value now; the curves and per-leaf
  # animations are hl.curve(...) / hl.animation(...) calls (see extraConfig).
  wayland.windowManager.hyprland.settings.config.animations.enabled = true;

  wayland.windowManager.hyprland.settings.config.general = {
    gaps_in = 4;
    gaps_out = 12;
    border_size = 3;
    col = {
      # Gradient: hyprlang "rgba(a) rgba(b) 45deg" -> { colors = {..}, angle = 45 }
      active_border = {
        colors = [
          "rgba(ffcce6ff)"
          "rgba(9778D0ff)"
        ];
        angle = 45;
      };
      inactive_border = "rgba(595959aa)";
    };
  };

  # Curves + animations must be hand-written Lua (hl.curve / hl.animation).
  # Curves are declared before the animations that reference them.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.curve("linear",    { type = "bezier", points = { {0.5, 0.5}, {0.5, 0.5} } })
    hl.curve("overshoot", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.1} } })
    hl.curve("goofy",     { type = "bezier", points = { {0.2, 1.6}, {0.4, 1.5} } })

    hl.animation({ leaf = "windows",    enabled = true, speed = 6, bezier = "goofy",   style = "popin" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "goofy",   style = "popin" })
    hl.animation({ leaf = "fade",       enabled = true, speed = 5, bezier = "default" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default", style = "slidefade 20%" })
  '';

  # Cursor
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.catppuccin-cursors.mochaPink;
    name = "catppuccin-mocha-pink-cursors";
    size = 16;
  };
  wayland.windowManager.hyprland.settings.env = [
    { _args = [ "HYPRCURSOR_THEME" "catppuccin-mocha-pink-cursors" ]; }
    { _args = [ "HYPRCURSOR_SIZE" "16" ]; }
    { _args = [ "XCURSOR_THEME" "catppuccin-mocha-pink-cursors" ]; }
    { _args = [ "XCURSOR_SIZE" "16" ]; }
  ];
  # Disable hardware cursors to fix Hyprland rendering bugs
  wayland.windowManager.hyprland.settings.config.cursor = {
    no_hardware_cursors = true;
  };
}
