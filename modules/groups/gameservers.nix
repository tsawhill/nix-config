{
  config,
  lib,
  ...
}:

let
  cfg = config.my.groups.gameservers;
  groupOptions = import ./options.nix;
in
{
  options.my.groups.gameservers = lib.mkOption {
    type = lib.types.submodule groupOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.groups.gameservers = {
      inherit (cfg) members;
    }
    // lib.optionalAttrs (cfg.gid != null) {
      gid = cfg.gid;
    };
  };
}
