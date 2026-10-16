{ lib, pkgs, ... }:
{
  software.games.entries.cloneHero = {
    command = "clone-hero";
    desktopName = "Clone Hero";
    category = "Clone Hero";
    runner.native.command = lib.getExe pkgs.clonehero;
  };
}
