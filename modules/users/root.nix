{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.users.root;
in
{
  options.my.users.root = lib.mkOption {
    type = lib.types.submodule (args: import ./options.nix (args // { inherit pkgs; }));
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.users."root" = {
      inherit (cfg) shell;
      inherit (cfg) extraGroups;
    }
    // lib.optionalAttrs (cfg.uid != null) {
      uid = cfg.uid;
    };
  };
}
