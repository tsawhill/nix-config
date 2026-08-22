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

  # NixOS atomically replaces the system profile during a switch, which leaves
  # Elephant's desktop-entry watcher attached to the previous store path.
  # Restart the persistent backend and frontend whenever that profile changes.
  systemd.user.services = {
    elephant.Unit.X-Restart-Triggers = [ osConfig.system.path ];
    walker.Unit.X-Restart-Triggers = [ osConfig.system.path ];
  };
}
