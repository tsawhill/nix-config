{ config, lib, ... }:
# All windows default to 99% inactive opacity.
# Add classes to dimApps for 97% inactive opacity.
# Add raw match strings to opaqueApps to exempt windows from dimming (full inactive opacity).
# Both lists are additive — definitions across modules are concatenated.
{
  options.my.hypr.windowRules.transparency.enable = lib.mkEnableOption "transparency window rules" // { default = true; };

  options.my.hypr.transparency = {
    dimApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Window classes to dim to 97% opacity when inactive.";
    };
    opaqueApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Raw match strings (e.g. \"title .*YouTube\", \"class foo\") to keep at full inactive opacity.";
    };
  };

  config = lib.mkIf config.my.hypr.windowRules.transparency.enable {
    my.hypr.transparency = {
      dimApps = [ "foot" "vesktop" "feishin" ];
      opaqueApps = [
        "title .*- YouTube — Zen Browser"
        "title .*tv — Zen Browser"
        "title .*Kick — Zen Browser"
        "title .*'s Stream"
        "class cafe.avery.Delfin"
      ];
    };

    wayland.windowManager.hyprland.settings.windowrule =
      [ "opacity 1.0 override 0.99 override, match:class .+" ]
      ++ map (m: "opacity 1.0 override 1.0 override, match:${m}") config.my.hypr.transparency.opaqueApps
      ++ map (c: "opacity 1.0 override 0.97 override, match:class ${c}") config.my.hypr.transparency.dimApps;
  };
}
