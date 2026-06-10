{
  config,
  lib,
  pkgs,
  ...
}:

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
            passwordSecretPath = lib.mkOption {
              type = lib.types.path;
              description = "Path to the decrypted SOPS secret containing the plaintext password";
            };
            extraGroups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
        }
      );
    };

    defaultUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default Samba users allowed to access shares when a share does not override users.";
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
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "Users allowed to access this share. Defaults to my.shares.defaultUsers when unset.";
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
    # Create System Users
    users.users = lib.mapAttrs (name: ucfg: {
      isNormalUser = true;
      description = "Samba user - ${name}";
      inherit (ucfg) extraGroups;
    }) (lib.filterAttrs (n: v: v.enable) cfg.users);

    # Configure Samba
    services.samba.settings = lib.mapAttrs (name: scfg: {
      "path" = scfg.path;
      "browseable" = "yes";
      "read only" = if scfg.readOnly then "yes" else "no";
      "guest ok" = "no";
      "valid users" = lib.concatStringsSep " " (if scfg.users == null then cfg.defaultUsers else scfg.users);
      "create mask" = "0664";
      "directory mask" = "0775";
    }) (lib.filterAttrs (n: v: v.enable) cfg.definitions);

    # Dynamically Generate Password Sync Services
    systemd.services = lib.mapAttrs' (
      name: ucfg:
      lib.nameValuePair "sync-samba-pass-${name}" {
        description = "Sync plaintext SOPS password to Linux and Samba for ${name}";
        wantedBy = [ "multi-user.target" ];

        # We removed the 'after' and 'requires' lines here

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          # Read plaintext password
          PASS=$(cat ${ucfg.passwordSecretPath})

          # Sync to Linux Shadow
          echo "${name}:$PASS" | ${pkgs.shadow}/bin/chpasswd

          # Sync to Samba DB
          (echo "$PASS"; echo "$PASS") | ${pkgs.samba}/bin/smbpasswd -s -a ${name}
        '';
      }
    ) (lib.filterAttrs (n: v: v.enable) cfg.users);
  };
}
