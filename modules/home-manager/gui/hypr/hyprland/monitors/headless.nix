{
  lib,
  config,
  ...
}:
{
  options.my.hypr.monitors.headless.enable =
    lib.mkEnableOption "Headless monitor config (for sunshine)";

  config = lib.mkIf config.my.hypr.monitors.headless.enable {
    wayland.windowManager.hyprland.settings.monitor = [
      {
        output = "HEADLESS-2";
        mode = "3840x2160@60";
        position = "0x10000";
        scale = 1;
      }
    ];
    wayland.windowManager.hyprland.extraConfig = ''
      hl.exec_cmd("hyprctl output create headless HEADLESS-2")
      hl.workspace_rule({ workspace = "11", monitor = "HEADLESS-2", default = true })
    '';
  };
}
