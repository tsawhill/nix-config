{ config, lib, ... }:
let
  server = config.my.shell.starshipTheme == "server";
in
{
  options.my.shell.starshipTheme = lib.mkOption {
    type = lib.types.enum [
      "server"
      "personal"
    ];
    default = "server";
    description = "Prompt palette: amber with user@host on servers, Tokyo Night on personal machines.";
  };

  config.programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    settings = import ./starship-settings.nix server;
  };
}
