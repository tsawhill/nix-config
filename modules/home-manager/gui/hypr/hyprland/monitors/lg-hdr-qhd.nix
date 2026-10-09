{ lib, config, ... }:
{
  options.my.hypr.monitors.lgHdrQhd.enable = lib.mkEnableOption "LG HDR QHD monitor config" // {
    default = true;
  };

  config = lib.mkIf config.my.hypr.monitors.lgHdrQhd.enable {
    wayland.windowManager.hyprland.settings.monitor = [
      {
        output = "desc:LG Electronics LG HDR QHD 102NTHMA2713";
        mode = "2560x1440@74.97Hz";
        position = "0x0";
        scale = 1;
        bitdepth = 8;
        supports_hdr = -1;
        cm = "srgb";
      }
    ];
  };
}
