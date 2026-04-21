{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.my.yarg;
  yarc-launcher = pkgs.callPackage ../../../../pkgs/yarc-launcher.nix { };
in
{
  options.my.yarg.enable = lib.mkEnableOption "YARG launcher desktop entries";

  config = lib.mkIf (cfg.enable && config.wayland.windowManager.hyprland.enable) {
    home.packages = [ yarc-launcher ];

    xdg.desktopEntries = {
      yarg-43 = {
        name = "YARG 4:3";
        comment = "Launch YARG Launcher in gamescope at 1920x1440";
        exec = ''hyprctl dispatch exec "[workspace active;float] env DISABLE_MANGOHUD=1 PIPEWIRE_QUANTUM=64/48000 gamescope -W 1920 -H 1440 -w 1920 -h 1440 -- yarc-launcher"'';
        icon = "yarc-launcher";
        type = "Application";
        terminal = false;
        categories = [ "Game" ];
      };

      yarg-169 = {
        name = "YARG 16:9";
        comment = "Launch YARG Launcher in gamescope at 2560x1440";
        exec = ''hyprctl dispatch exec "[workspace active;float] env DISABLE_MANGOHUD=1 PIPEWIRE_QUANTUM=64/48000 gamescope -W 2560 -H 1440 -w 2560 -h 1440 -- yarc-launcher"'';
        icon = "yarc-launcher";
        type = "Application";
        terminal = false;
        categories = [ "Game" ];
      };
    };
  };
}
