{ pkgs, ... }:
{
  # Use the hyprland portal for file pickers, screen sharing, etc.
  # gtk must be in extraPortals here (not just system packages) so gtk.portal
  # lands in the user profile where xdg-desktop-portal scans for backends.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.hyprland.default = [ "hyprland" "gtk" ];
}
