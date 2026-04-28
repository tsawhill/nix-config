{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.alienware165.enable = lib.mkEnableOption "desktop monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.alienware165.enable {

    wayland.windowManager.hyprland.extraConfig = ''
      monitorv2 {
        output=desc:Dell Inc. AW3423DWF 3D442S3
        mode=3440x1440@165Hz
        position=auto-right
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
        vrr=0
      }
    '';
  };
}
