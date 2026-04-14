{ lib, config, ... }:
{
  imports = [ ./themes/pink.nix ];

  options.my.hypr.lock.theme = lib.mkOption {
    type = lib.types.str;
    default = "pink";
    description = "Hyprlock theme. Add a corresponding file in themes/ and guard with lib.mkIf.";
  };

  config.programs.hyprlock.enable = true;
}
