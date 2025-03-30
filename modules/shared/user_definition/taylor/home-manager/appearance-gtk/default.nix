{ pkgs, ... }:
{
  # GTK theming settings
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
  };
}
