{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.headless.enable =
    lib.mkEnableOption "Headless monitor config (for sunshine)";

  config = lib.mkIf config.my.hypr.monitors.headless.enable {
    wayland.windowManager.hyprland.extraConfig = ''
      monitorv2 {
        output=HEADLESS-2
        mode=3840x2160@60
        position=0x10000
        scale=1
      }
      workspace = 11,monitor:HEADLESS-2,default:true
      exec=hyprctl output create headless HEADLESS-2
    '';
  };
}
