{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf (osConfig.my.hypr.launcher == "walker") {
  services.elephant.enable = true;

  services.walker = {
    enable = true;
    package = pkgs.walker;
    systemd.enable = true;
    settings = {
      app_launch_prefix = lib.mkIf osConfig.programs.hyprland.withUWSM "uwsm app --";
      # '>' prefix exclusively triggers runner in normal walker search
      providers.prefixes = [
        {
          prefix = ">";
          provider = "runner";
        }
      ];
    };
  };
}
