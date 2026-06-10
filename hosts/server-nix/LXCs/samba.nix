{ self, config, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/samba"
  ];
  my.secrets.immobile0783-pass.enable = true;
  my.secrets.umbriel-pass.enable = true;
  my.secrets.pelican8334-pass.enable = true;
  my.shares = {
    defaultUsers = [
      "immobile0783"
      "umbriel"
      "pelican8334"
    ];
    users = {
      # taylor-desktop-nix
      immobile0783 = {
        enable = true;
        passwordSecretPath = config.sops.secrets.immobile0783-pass.path;
        extraGroups = [
          "media"
          "download"
          "gameservers"
          "code"
          "games"
        ];
      };
      # taylor-laptop-nix
      umbriel = {
        enable = true;
        passwordSecretPath = config.sops.secrets.umbriel-pass.path;
        extraGroups = [
          "media"
          "download"
          "gameservers"
          "code"
          "games"
        ];
      };
      # taylor-deck-nix
      pelican8334 = {
        enable = true;
        passwordSecretPath = config.sops.secrets.pelican8334-pass.path;
        extraGroups = [
          "media"
          "download"
          "gameservers"
          "code"
          "games"
        ];
      };
    };
    definitions = {
      nix-configs = {
        enable = true;
        path = "/mnt/zpool/code/nix-config";
      };
      media = {
        enable = true;
        path = "/mnt/zpool/media";
        readOnly = true;
      };
      gameSSD = {
        enable = true;
        path = "/mnt/gameSSD";
      };
    };
  };
  my.groups = {
    media = {
      enable = true;
      members = [ "root" ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [ "root" ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [ "root" ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [ "root" ];
      gid = 1003;
    };
    games = {
      enable = true;
      members = [ "root" ];
      gid = 1005;
    };
  };

  networking.hostName = "samba-nix";
}
