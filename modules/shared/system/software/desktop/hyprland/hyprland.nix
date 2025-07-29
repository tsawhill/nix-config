{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{

  # Hyprland Config
  programs.hyprland = {
    enable = true;
    # package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # portalPackage =
      # inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    withUWSM = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    waybar
    hyprpanel
    walker
    grimblast
    libnotify
    wl-clipboard
    hyprpaper
    linux-wallpaperengine
    hyprlock
    hyprcursor
    hyprpolkitagent
  ];
}
