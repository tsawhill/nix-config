{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
 
 # Hyprland Config
   # programs.uwsm.enable = true;
   programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Polkit config for Hyprland
  security.polkit.enable = true;


  environment.systemPackages = with pkgs; [
    waybar
    hyprpanel
    inputs.walker.packages.${system}.default
    grimblast
    libnotify
    wl-clipboard
    hyprpaper
    linux-wallpaperengine
    hyprlock
    hyprcursor
    hyprpolkitagent

    # For xembedsniproxy, xwayland applications system tray
    kdePackages.plasma-workspace
   
  ];
}
