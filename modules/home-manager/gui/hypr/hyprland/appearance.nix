{ pkgs, ... }:
{
  # Decoration settings -> hl.config({ decoration = { ... } })
  wayland.windowManager.hyprland.settings.config.decoration = {
    rounding = 12;
    blur = {
      enabled = true;
      size = 6;
      passes = 3; # Multiple passes create a much smoother, frosted glass look
      ignore_opacity = false; # Ensures blur works nicely with window transparency
    };
    shadow = {
      enabled = true;
      range = 26; # Broad, soft shadow
      render_power = 3; # Softer falloff
      color = "rgba(100d2066)"; # Subtle purple tint
    };
  };

  # Only the enable flag is a config value now; the curves and per-leaf
  # animations are hl.curve(...) / hl.animation(...) calls (see extraConfig).
  wayland.windowManager.hyprland.settings.config.animations.enabled = true;

  wayland.windowManager.hyprland.settings.config.general = {
    gaps_in = 6;
    gaps_out = 14;
    border_size = 2;
    col = {
      # Gradient: hyprlang "rgba(a) rgba(b) 45deg" -> { colors = {..}, angle = 45 }
      active_border = {
        colors = [
          "rgba(ffcce6ff)"
          "rgba(c4a7e7ff)"
          "rgba(9ccfd8ff)"
        ];
        angle = 45;
      };
      inactive_border = "rgba(63639466)";
    };
  };

  # Curves + animations must be hand-written Lua (hl.curve / hl.animation).
  # Curves are declared before the animations that reference them.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.curve("smooth",    { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })
    hl.curve("pop",       { type = "bezier", points = { {0.18, 1.35}, {0.3, 1} } })
    hl.curve("sweep",     { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })

    -- Smooth layout changes, with a more playful overshoot on window entrances.
    hl.animation({ leaf = "windows",    enabled = true, speed = 4.5, bezier = "smooth" })
    hl.animation({ leaf = "windowsIn",  enabled = true, speed = 5,   bezier = "pop",    style = "popin 80%" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.5, bezier = "smooth", style = "popin 90%" })
    hl.animation({ leaf = "fade",       enabled = true, speed = 3,   bezier = "smooth" })
    hl.animation({ leaf = "border",     enabled = true, speed = 3,   bezier = "smooth" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "sweep",  style = "slidefade 25%" })
  '';

  # Cursor
  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.comixcursors.Opaque_Orange;
    name = "ComixCursors-Opaque-Orange";
    size = 24;
  };
  wayland.windowManager.hyprland.settings.env = [
    { _args = [ "HYPRCURSOR_THEME" "ComixCursors-Opaque-Orange" ]; }
    { _args = [ "HYPRCURSOR_SIZE" "24" ]; }
    { _args = [ "XCURSOR_THEME" "ComixCursors-Opaque-Orange" ]; }
    { _args = [ "XCURSOR_SIZE" "24" ]; }
  ];
  # Disable hardware cursors to fix Hyprland rendering bugs
  wayland.windowManager.hyprland.settings.config.cursor = {
    no_hardware_cursors = true;
  };
}
