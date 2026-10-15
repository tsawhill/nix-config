{ config, lib, ... }:
# Popup styling; Wayle's shared toggle helper handles size and click-relative position.
# Add to config.my.hypr.taskbarPopups from any module/host — definitions are concatenated.
let
  mkPopupRules = class: [
    {
      match = { class = class; };
      float = true;
      rounding = 16; # Rounder than global default (12)
      opacity = "0.88 0.88"; # Frosted glass — pairs with global blur
      border_color = "rgba(ffcce6ff) rgba(c4a7e7ff) rgba(9ccfd8ff) 45deg"; # Match the active window gradient
    }
  ];
in
{
  options.my.hypr.windowRules.taskbarPopups.enable = lib.mkEnableOption "taskbar popup window rules" // { default = true; };

  options.my.hypr.taskbarPopups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Window classes to style as floating taskbar popups; Wayle handles positioning.";
  };

  config = lib.mkIf config.my.hypr.windowRules.taskbarPopups.enable {
    my.hypr.taskbarPopups = [
      ".blueman-manager-wrapped"
      "blueman-manager"
      "org.pulseaudio.pavucontrol"
      "pavucontrol"
      "nm-connection-editor"
      "dev.periph.mchose-m7-ultra"
    ];
    my.hypr.transparency.opaqueApps = [ "class dev.periph.mchose-m7-ultra" ];


    wayland.windowManager.hyprland.settings.window_rule =
      lib.concatMap mkPopupRules config.my.hypr.taskbarPopups
      ++ [
        # Start hidden so the helper can size and position each window before revealing it.
        { match.class = "(org\\.pulseaudio\\.pavucontrol|pavucontrol)"; workspace = "special:wayle-volume silent"; }
        { match.class = "nm-connection-editor"; workspace = "special:wayle-network silent"; }
        { match.class = "(\\.blueman-manager-wrapped|blueman-manager)"; workspace = "special:wayle-bluetooth silent"; }
        {
          match.class = "dev.periph.mchose-m7-ultra";
          workspace = "special:wayle-mouse silent";
        }
      ];
  };
}
