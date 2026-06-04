# Shared, data-driven Syncthing module.
#
# A host enables it, declares which device in the fleet it is, and the module
# derives its peers and folders from ./fleet.nix. Every device that shares a
# folder with this host is added as a trusted device automatically.
{ config, lib, ... }:

let
  cfg = config.my.syncthing;
  fleet = import ./fleet.nix;
  me = cfg.device;

  # Effective local path for a share: per-host override, else the fleet default.
  effPath = name: cfg.sharePaths.${name} or (fleet.shares.${name}.devices.${me} or null);

  # Shares this host actually participates in (has a non-null effective path).
  myShareNames = lib.filter (name: effPath name != null) (lib.attrNames fleet.shares);

  # Members of a share other than this host.
  sharedevices = name: lib.subtractLists [ me ] (lib.attrNames fleet.shares.${name}.devices);

  # All peer devices this host shares at least one folder with -> trusted devices.
  peerNames = lib.unique (lib.concatMap sharedevices myShareNames);

  mkDevice =
    name:
    let
      d = fleet.devices.${name};
    in
    { inherit (d) id; }
    // lib.optionalAttrs ((d.addresses or [ ]) != [ ]) { inherit (d) addresses; };

  mkFolder = name: {
    path = effPath name;
    devices = sharedevices name; # self is implicit in syncthing
  };
in
{
  options.my.syncthing = {
    enable = lib.mkEnableOption "Syncthing fleet sync";

    device = lib.mkOption {
      type = lib.types.str;
      description = "This host's key in ./fleet.nix `devices`.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "syncthing";
      description = "User the syncthing service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "syncthing";
      description = "Group the syncthing service runs as.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "sops YAML file holding `syncthing_key` and `syncthing_cert` for this host.";
    };

    sharePaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        roms = "/data/roms";
      };
      description = "Per-host overrides of a share's local path, replacing the fleet.nix default.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = fleet.devices ? ${me};
        message = "my.syncthing.device = \"${me}\" is not defined in modules/software/services/syncthing/fleet.nix";
      }
    ];

    sops.secrets."syncthing_key" = {
      sopsFile = cfg.credentialsFile;
      path = "/etc/syncthing/key.pem";
      owner = cfg.user;
      group = cfg.group;
      mode = "0600";
    };
    sops.secrets."syncthing_cert" = {
      sopsFile = cfg.credentialsFile;
      path = "/etc/syncthing/cert.pem";
      owner = cfg.user;
      group = cfg.group;
      mode = "0644";
    };

    services.syncthing = {
      enable = true;
      openDefaultPorts = true;
      inherit (cfg) user group;
      key = config.sops.secrets."syncthing_key".path;
      cert = config.sops.secrets."syncthing_cert".path;
      settings = {
        options.relaysEnabled = false;
        options.globalAnnounceEnabled = false;
        devices = lib.genAttrs peerNames mkDevice;
        folders = lib.genAttrs myShareNames mkFolder;
      };
    };
  };
}
