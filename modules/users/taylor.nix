{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.users.taylor;
  userOptions = import ./options.nix;
in
{
  options.my.users.taylor = lib.mkOption {
    type = lib.types.submodule (args: import ./options.nix (args // { inherit pkgs; }));
    default = { };
  };

  config = lib.mkIf cfg.enable {
    users.users."taylor" = {
      inherit (cfg) shell;
      extraGroups = cfg.extraGroups ++ lib.optional cfg.sudoer "wheel";
      isNormalUser = true;
    }
    // lib.optionalAttrs (cfg.uid != null) {
      uid = cfg.uid;
    };
  };
}
