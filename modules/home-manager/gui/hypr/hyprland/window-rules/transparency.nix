{ config, lib, ... }:
# All windows default to 99% inactive opacity.
# Add classes to dimApps for 97% inactive opacity.
# Add raw match strings to opaqueApps to exempt windows from dimming (full inactive opacity).
# Both lists are additive — definitions across modules are concatenated.
let
  # Parse a raw "prop value" opaque-match string into a { prop = value; } table,
  # e.g. "title .*YouTube" -> { title = ".*YouTube"; }.
  mkMatch =
    m:
    let
      parts = lib.splitString " " m;
    in
    {
      ${lib.head parts} = lib.concatStringsSep " " (lib.tail parts);
    };
in
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

    wayland.windowManager.hyprland.settings.window_rule =
      [
        {
          match = { class = ".+"; };
          opacity = "1.0 override 0.99 override";
        }
      ]
      ++ map (c: {
        match = { class = c; };
        opacity = "1.0 override 0.97 override";
      }) config.my.hypr.transparency.dimApps
      ++ map (m: {
        match = mkMatch m;
        opacity = "1.0 override 1.0 override";
      }) config.my.hypr.transparency.opaqueApps;
  };
}
