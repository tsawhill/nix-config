{ config, pkgs, ... }:
{
  gtk = {
    enable = true;
    cursorTheme = {
      name = "catppuccin-mocha-pink-cursors";
      size = 24;
      package = pkgs.catppuccin-cursors.mochaPink;
    };
    # Was Orchis-Purple-Light until 2026-07-31. nixpkgs dropped orchis-theme —
    # along with every other murrine-based theme (colloid, graphite, arc,
    # magnetic-catppuccin, …) — when gtk-engine-murrine was removed as an
    # unmaintained GTK2 dependency. catppuccin-gtk is the closest survivor:
    # latte = light, mauve = purple, matching the old theme's look and the
    # pink/purple cursor + icon themes below.
    theme = {
      name = "catppuccin-latte-mauve-standard";
      package = pkgs.catppuccin-gtk.override {
        variant = "latte";
        accents = [ "mauve" ];
      };
    };
    iconTheme = {
      name = "Tela-pink";
      package = pkgs.tela-icon-theme;
    };
    font = {
      name = "DaddyTimeMono Nerd Font";
      package = pkgs.nerd-fonts.daddy-time-mono;
    };
    gtk2 = {
      configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
      force = true;
    };
    gtk4.theme = null;
  };
}
