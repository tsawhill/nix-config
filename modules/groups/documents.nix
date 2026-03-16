{
  config,
  lib,
  ...
}:

let
  cfg = config.my.groups.documents;
  groupOptions = import ./options.nix;
in
{
  options.my.groups.documents = lib.mkOption {
    type = lib.types.submodule groupOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.groups.documents = {
      inherit (cfg) members;
    }
    // lib.optionalAttrs (cfg.gid != null) {
      gid = cfg.gid;
    };
  };
}
