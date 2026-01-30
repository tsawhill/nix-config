{ config, lib, ... }:

let
  cfg = config.my.shares;
in
{
  options.my.shares = {
    # User definition
    users = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Samba user account";
            extraGroups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
        }
      );
    };

    # Share definition
    definitions = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable this samba share";
            path = lib.mkOption { type = lib.types.path; };
            users = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            readOnly = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
          };
        }
      );
    };
  };

  config = {
    # 1. Create System Users
    users.users = lib.mapAttrs (name: ucfg: {
      isNormalUser = true;
      description = "Samba user - ${name}";
      inherit (ucfg) extraGroups;
    }) (lib.filterAttrs (n: v: v.enable) cfg.users);

    # 2. Configure Samba
    services.samba.settings = lib.mapAttrs (name: scfg: {
      "path" = scfg.path;
      "browseable" = "yes";
      "read only" = if scfg.readOnly then "yes" else "no";
      "guest ok" = "no";
      "valid users" = lib.concatStringsSep " " scfg.users;
      "create mask" = "0644";
      "directory mask" = "0755";
    }) (lib.filterAttrs (n: v: v.enable) cfg.definitions);
  };
}
