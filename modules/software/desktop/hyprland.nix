{ pkgs, lib, config, ... }:
{
  options.desktop.hyprland.enable = lib.mkEnableOption "Hyprland wayland compositor";

  config = lib.mkIf config.desktop.hyprland.enable {
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # GTK portal needed alongside hyprland's own portal for file pickers etc.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.systemPackages = with pkgs; [
    walker
    elephant
    grimblast
    libnotify
    wl-clipboard
    hyprlock
    hyprcursor
    hyprpolkitagent
  ];
  };
}
