# Shared, data-driven Syncthing module.
#
# A host enables it, declares which device in the fleet it is, and the module
# derives its peers and folders from ./fleet.nix. Every device that shares a
# folder with this host is added as a trusted device automatically.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.syncthing;
  fleet = import ./fleet.nix;
  me = cfg.device;

  # External (non-NixOS) devices, and the shares each of them joins.
  externalNames = lib.attrNames (lib.filterAttrs (_: d: d.external or false) fleet.devices);
  externalMembersOf =
    name: lib.filter (e: lib.elem name (fleet.devices.${e}.shares or [ ])) externalNames;

  # All members of a share = its NixOS members plus any external devices that
  # declared it. Self is excluded (it is implicit to syncthing).
  membersOf = name: fleet.shares.${name}.members ++ externalMembersOf name;
  folderPeers = name: lib.subtractLists [ me ] (lib.unique (membersOf name));

  # Effective local path for a share: per-host override, else the per-device
  # override in the fleet, else the share's default path.
  effPath =
    name:
    let
      s = fleet.shares.${name};
    in
    if !(lib.elem me s.members) then
      null
    else
      cfg.sharePaths.${name} or ((s.overrides or { }).${me} or s.path);

  # Shares this host participates in (it is a member).
  myShareNames = lib.filter (name: effPath name != null) (lib.attrNames fleet.shares);

  # All peer devices this host shares at least one folder with -> trusted devices.
  peerNames = lib.unique (lib.concatMap folderPeers myShareNames);

  mkDevice =
    name:
    let
      d = fleet.devices.${name};
    in
    { inherit (d) id; }
    // lib.optionalAttrs ((d.addresses or [ ]) != [ ]) { inherit (d) addresses; };

  mkFolder = name: {
    path = effPath name;
    devices = folderPeers name; # self is implicit in syncthing
  };

  # Per-host ignore patterns (raw .stignore lines) from this device's fleet
  # entry, written into every folder this host participates in.
  myIgnores = fleet.devices.${me}.ignores or [ ];
  stignoreFile = pkgs.writeText "syncthing-stignore-${me}" (lib.concatStringsSep "\n" myIgnores + "\n");
  myFolderPaths = map effPath myShareNames;
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

    # Write this host's ignore patterns into each folder's .stignore before
    # syncthing starts, so it never indexes/syncs the excluded directories.
    systemd.services.syncthing-stignore = lib.mkIf (myIgnores != [ ]) {
      description = "Write Syncthing .stignore files for ${me}";
      wantedBy = [ "multi-user.target" ];
      requiredBy = [ "syncthing.service" ];
      before = [
        "syncthing.service"
        "syncthing-init.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatMapStringsSep "\n" (path: ''
        if [ -d ${lib.escapeShellArg path} ]; then
          install -m 0644 -o ${cfg.user} -g ${cfg.group} ${stignoreFile} ${lib.escapeShellArg (path + "/.stignore")}
        fi
      '') myFolderPaths;
    };
  };
}
