{
  # Monitors are pinned to cm=hdr; auto-hdr strips the display's HDR metadata when a
  # fullscreen window advertises SDR, leaving PQ output on an SDR display (washed out).
  wayland.windowManager.hyprland.settings.config.render.cm_auto_hdr = 0;
}
