{ config, lib, ... }:
let
  # Must match Moonlight's stream resolution setting.
  stream = { w = 1180; h = 820; };
in
{
  options.my.hypr.windowRules.secondaryMonitor.enable = lib.mkEnableOption "secondary monitor window rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.secondaryMonitor.enable {
    wayland.windowManager.hyprland.settings.window_rule = [
      # Keep Vesktop's preferred content size inside the remaining tile.
      {
        match = { class = "vesktop"; };
        float = false;
        pseudo = true;
        size = "2123 1209";
      }
      # The stream window is titled after the host, not the app.
      {
        match = {
          class = "^com\\.moonlight_stream\\.Moonlight$";
          title = "^sunshine-nix - Moonlight$";
        };
        workspace = "6 silent";
        float = false;
        pseudo = true;
        size = "${toString stream.w} ${toString stream.h}";
        suppress_event = "fullscreen maximize";
      }
    ];

    # Workspace 6: streams in a native-width left column, everything else right.
    wayland.windowManager.hyprland.extraConfig = ''
      dofile("${./workspace-layouts.lua}").secondary(${toString stream.w})
    '';
  };
}
