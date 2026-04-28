{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.alienware360.enable = lib.mkEnableOption "desktop monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.alienware360.enable {

    home.activation.writeAlienware360MonitorConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.config/hypr/monitors"
      cat > "$HOME/.config/hypr/monitors/alienware360.conf" << 'MONITOREOF'
monitorv2 {
  output=desc:Dell Inc. AW2725DF CJ56ZZ3
  mode=2560x1440@360Hz
  position=0x0
  scale=1
  bitdepth=10
  supports_hdr=true
  cm=hdr
  sdr_min_luminance = 0.005
  sdr_max_luminance = 240
  min_luminance = 0
  max_luminance = 400
  max_avg_luminance = 300
  supports_wide_color = true
  sdr_brightness = 1.00
  vrr=0
}
MONITOREOF
    '';

    wayland.windowManager.hyprland.extraConfig = ''
      exec-once = sed -i 's/sdr_brightness = [0-9.]*/sdr_brightness = 1.00/' ~/.config/hypr/monitors/alienware360.conf
      source = ~/.config/hypr/monitors/alienware360.conf
    '';
  };
}
