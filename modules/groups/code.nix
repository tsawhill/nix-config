{
  config,
  lib,
  ...
}:

let
  cfg = config.my.groups.code;
  groupOptions = import ./options.nix;
in
{
  options.my.groups.code = lib.mkOption {
    type = lib.types.submodule groupOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.groups.code = {
      inherit (cfg) members;
    }
    // lib.optionalAttrs (cfg.gid != null) {
      gid = cfg.gid;
    };
  };
}
