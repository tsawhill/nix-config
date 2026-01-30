{ lib, pkgs, ... }:

{
  options = {
    enable = lib.mkEnableOption "Enable user";

    uid = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1001;
      description = "The ID of the user. If null, NixOS will choose one.";
    };

    sudoer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this user can use sudo";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "A list of groups this user will be added to.";
    };

    shell = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zsh;
      description = "The shell package the user should use.";
    };
  };
}
