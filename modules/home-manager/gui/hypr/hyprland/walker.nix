{
  lib,
  inputs,
  osConfig,
  ...
}:
{
  imports = [ inputs.walker.homeManagerModules.default ];

  programs.walker = lib.mkIf (osConfig.my.hypr.launcher == "walker") {
    enable = true;
    runAsService = true;
    config = {
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
