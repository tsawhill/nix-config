{ config, pkgs, ... }:
{
  gtk = {
    enable = true;
    cursorTheme = {
      name = "catppuccin-mocha-pink-cursors";
      size = 24;
      package = pkgs.catppuccin-cursors.mochaPink;
    };
    theme = {
      name = "Orchis-Purple-Light";
      package = pkgs.orchis-theme;
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
