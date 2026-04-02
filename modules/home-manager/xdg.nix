{ config, ... }:
{
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      extraConfig = {
        SCREENSHOTS = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
  };
}
