{ pkgs, lib, config, ... }:
{
  options.desktop.gnome.enable = lib.mkEnableOption "GNOME desktop environment";

  config = lib.mkIf config.desktop.gnome.enable {
    services.xserver.enable = true;

    services.desktopManager.gnome.enable = true;

    # Remove default GNOME bloat
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      gnome-connections
      epiphany
      geary
    ];

    environment.systemPackages = with pkgs; [
      gnome-tweaks
      dconf-editor
    ];
  };
}
