{ lib, ... }:

{
  options = {
    enable = lib.mkEnableOption "Enable group";

    members = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "root"
        "taylor"
      ];
      description = "A list of users who will be a member of this group.";
    };

    gid = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 1001;
      description = "The ID of the group. If null, NixOS will choose one.";
    };
  };
}
