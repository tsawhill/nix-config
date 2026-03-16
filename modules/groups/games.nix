{
  config,
  lib,
  ...
}:

let
  cfg = config.my.groups.games;
  groupOptions = import ./options.nix;
in
{
  options.my.groups.games = lib.mkOption {
    type = lib.types.submodule groupOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.groups.games = {
      inherit (cfg) members;
    }
    // lib.optionalAttrs (cfg.gid != null) {
      gid = cfg.gid;
    };
  };
}
