{
  wayland.windowManager.hyprland.settings.config.input = {
    kb_layout = "us";
    follow_mouse = 2;
    float_switch_override_focus = 0;
    accel_profile = "flat";
    sensitivity = -0.4;
    touchpad = {
      tap_and_drag = true;
      natural_scroll = true;
      scroll_factor = 0.5;
    };
  };

  # hl.gesture({ ... }) — one call per list element.
  wayland.windowManager.hyprland.settings.gesture = [
    {
      fingers = 3;
      direction = "horizontal";
      action = "workspace";
    }
  ];
}
