{
  config,
  lib,
  ...
}:

let
  cfg = config.my.groups.download;
  groupOptions = import ./options.nix;
in
{
  options.my.groups.download = lib.mkOption {
    type = lib.types.submodule groupOptions;
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.groups.download = {
      inherit (cfg) members;
    }
    // lib.optionalAttrs (cfg.gid != null) {
      gid = cfg.gid;
    };
  };
}
