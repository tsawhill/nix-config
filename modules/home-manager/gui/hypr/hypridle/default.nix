{ lib, ... }:
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # Scope the home-manager generated service to the Hyprland session only
  systemd.user.services.hypridle = {
    Unit = {
      After = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
      PartOf = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
    };
    Install.WantedBy = lib.mkForce [ "wayland-session@hyprland.desktop.target" ];
  };
}
