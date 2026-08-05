{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.palworld;

  settingsDirectory = "${cfg.dataDir}/Pal/Saved/Config/LinuxServer";
  settingsFile = "${settingsDirectory}/PalWorldSettings.ini";

  boolString = value: if value then "True" else "False";
  quotedString = value: builtins.toJSON value;

  managedSettings = {
    ServerName = quotedString cfg.serverName;
    ServerDescription = quotedString cfg.serverDescription;
    ServerPlayerMaxNum = toString cfg.maxPlayers;
    CrossplayPlatforms = "(${lib.concatStringsSep "," cfg.crossplayPlatforms})";
    bIsUseBackupSaveData = boolString cfg.useBackupSaveData;
    RCONEnabled = boolString cfg.rcon.enable;
    RCONPort = toString cfg.rcon.port;
    RESTAPIEnabled = boolString cfg.restApi.enable;
    RESTAPIPort = toString cfg.restApi.port;
  }
  // cfg.extraSettings;

  managedSettingsFile = pkgs.writeText "palworld-managed-settings.json" (
    builtins.toJSON managedSettings
  );

  settingsRenderer = pkgs.writeText "palworld-render-settings.py" ''
    import json
    import os
    import sys
    from pathlib import Path


    def split_fields(payload):
        fields = []
        start = 0
        depth = 0
        quoted = False
        escaped = False

        for index, character in enumerate(payload):
            if escaped:
                escaped = False
                continue
            if character == "\\" and quoted:
                escaped = True
                continue
            if character == '"':
                quoted = not quoted
                continue
            if quoted:
                continue
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            elif character == "," and depth == 0:
                fields.append(payload[start:index])
                start = index + 1

        fields.append(payload[start:])
        return fields


    managed_path = Path(sys.argv[1])
    template_path = Path(sys.argv[2])
    destination_path = Path(sys.argv[3])

    settings = json.loads(managed_path.read_text(encoding="utf-8"))

    server_password = os.environ.get("PALWORLD_SERVER_PASSWORD")
    admin_password = os.environ.get("PALWORLD_ADMIN_PASSWORD")
    if server_password is not None:
        settings["ServerPassword"] = json.dumps(server_password, ensure_ascii=False)
    if admin_password is not None:
        settings["AdminPassword"] = json.dumps(admin_password, ensure_ascii=False)

    lines = template_path.read_text(encoding="utf-8").splitlines()
    option_prefix = "OptionSettings=("
    option_line_index = None

    for index, line in enumerate(lines):
        if line.strip().startswith(option_prefix) and line.strip().endswith(")"):
            option_line_index = index
            break

    if option_line_index is None:
        raise RuntimeError(f"{template_path} does not contain an OptionSettings line")

    original_line = lines[option_line_index]
    indentation = original_line[: len(original_line) - len(original_line.lstrip())]
    stripped_line = original_line.strip()
    payload = stripped_line[len(option_prefix) : -1]
    fields = split_fields(payload)

    field_positions = {}
    for index, field in enumerate(fields):
        key, separator, _ = field.partition("=")
        if separator:
            field_positions[key.strip()] = index

    for key, value in settings.items():
        replacement = f"{key}={value}"
        if key in field_positions:
            fields[field_positions[key]] = replacement
        else:
            field_positions[key] = len(fields)
            fields.append(replacement)

    lines[option_line_index] = indentation + option_prefix + ",".join(fields) + ")"

    destination_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = destination_path.with_suffix(destination_path.suffix + ".tmp")
    temporary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary_path.chmod(0o600)
    temporary_path.replace(destination_path)
  '';

  installScript = pkgs.writeShellScript "palworld-install" ''
    set -euo pipefail

    ${pkgs.steamcmd}/bin/steamcmd \
      +force_install_dir ${lib.escapeShellArg cfg.dataDir} \
      +login anonymous \
      +app_update 2394010 validate \
      +quit

    test -x ${lib.escapeShellArg "${cfg.dataDir}/PalServer.sh"}
  '';

  renderSettingsScript = pkgs.writeShellScript "palworld-render-settings" ''
    set -euo pipefail

    ${pkgs.python3}/bin/python3 \
      ${settingsRenderer} \
      ${managedSettingsFile} \
      ${lib.escapeShellArg "${cfg.dataDir}/DefaultPalWorldSettings.ini"} \
      ${lib.escapeShellArg settingsFile}
  '';

  launchArguments = [
    "-port=${toString cfg.port}"
    "-players=${toString cfg.maxPlayers}"
  ]
  ++ lib.optionals cfg.communityServer [ "-publiclobby" ]
  ++ cfg.extraLaunchArguments;

  startScript = pkgs.writeShellScript "palworld-start" ''
    set -euo pipefail

    cd ${lib.escapeShellArg cfg.dataDir}
    exec ${pkgs.steam-run}/bin/steam-run ./PalServer.sh ${lib.escapeShellArgs launchArguments}
  '';

  updateCommand = pkgs.writeShellApplication {
    name = "palworld-update-server";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$EUID" -ne 0 ]; then
        echo "palworld-update-server must be run as root" >&2
        exit 1
      fi

      systemctl stop palworld.service
      systemctl restart palworld-install.service
      systemctl start palworld.service
    '';
  };
in
{
  options.services.palworld = {
    enable = lib.mkEnableOption "Palworld dedicated server";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Palworld server automatically at boot.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/palworld";
      description = "Mutable directory containing the server installation, configuration, and saves.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "palworld";
      description = "User account under which the server runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "palworld";
      description = "Group under which the server runs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8211;
      description = "UDP game port.";
    };

    maxPlayers = lib.mkOption {
      type = lib.types.ints.between 1 32;
      default = 16;
      description = "Maximum number of players.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "Palworld Server";
      description = "Name displayed by the Palworld server.";
    };

    serverDescription = lib.mkOption {
      type = lib.types.str;
      default = "Palworld dedicated server";
      description = "Description displayed by the Palworld server.";
    };

    communityServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise the server in the Palworld community server list.";
    };

    crossplayPlatforms = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "Steam"
          "Xbox"
          "PS5"
          "Mac"
        ]
      );
      default = [
        "Steam"
        "Xbox"
        "PS5"
        "Mac"
      ];
      description = "Platforms allowed to connect to the server.";
    };

    useBackupSaveData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Palworld's built-in world save backups.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional systemd environment file containing PALWORLD_SERVER_PASSWORD
        and PALWORLD_ADMIN_PASSWORD.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        Difficulty = "Normal";
        DayTimeSpeedRate = "1.000000";
      };
      description = "Additional raw values to merge into OptionSettings.";
    };

    extraLaunchArguments = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed to PalServer.sh.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the configured UDP game port in the NixOS firewall.";
    };

    rcon = {
      enable = lib.mkEnableOption "Palworld RCON";

      port = lib.mkOption {
        type = lib.types.port;
        default = 25575;
        description = "RCON TCP port.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the RCON port in the NixOS firewall.";
      };
    };

    restApi = {
      enable = lib.mkEnableOption "Palworld REST API";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8212;
        description = "REST API TCP port.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the REST API port in the NixOS firewall.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.rcon.enable || cfg.environmentFile != null;
        message = "services.palworld.rcon.enable requires services.palworld.environmentFile.";
      }
      {
        assertion = !cfg.restApi.enable || cfg.environmentFile != null;
        message = "services.palworld.restApi.enable requires services.palworld.environmentFile.";
      }
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${settingsDirectory} 0750 ${cfg.user} ${cfg.group} -"
    ];

    environment.systemPackages = [
      pkgs.steamcmd
      pkgs.steam-run
      updateCommand
    ];

    systemd.services.palworld-install = {
      description = "Install or update the Palworld dedicated server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = installScript;
        UMask = "0027";
      };
      environment = {
        HOME = cfg.dataDir;
      };
    };

    systemd.services.palworld = {
      description = "Palworld dedicated server";
      wantedBy = lib.optionals cfg.autoStart [ "multi-user.target" ];
      requires = [ "palworld-install.service" ];
      after = [
        "network-online.target"
        "palworld-install.service"
      ];
      wants = [ "network-online.target" ];
      preStart = "${renderSettingsScript}";
      environment = {
        HOME = cfg.dataDir;
        SteamAppId = "2394010";
      };
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = startScript;
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = "10s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "120s";
        LimitNOFILE = 100000;
        UMask = "0027";
      };
    };

    networking.firewall.allowedUDPPorts = lib.optionals cfg.openFirewall [ cfg.port ];
    networking.firewall.allowedTCPPorts =
      lib.optionals (cfg.rcon.enable && cfg.rcon.openFirewall) [ cfg.rcon.port ]
      ++ lib.optionals (cfg.restApi.enable && cfg.restApi.openFirewall) [ cfg.restApi.port ];
  };
}
