{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.gopeed;
  package = pkgs.callPackage ../../../pkgs/gopeed-web.nix { };
  stateDir = "/var/lib/gopeed";
in
{
  options.my.services.gopeed = {
    enable = lib.mkEnableOption "Gopeed, a web download manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9999;
      description = "Port Gopeed's web UI and API listen on.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "taylor";
      description = "Basic auth username. The password comes from the environment secret.";
    };

    downloadDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/downloadHDD/gopeed";
      description = "Default save directory. Gopeed only reads it on first start; later changes live in the web UI.";
    };

    environmentSecret = lib.mkOption {
      type = lib.types.str;
      default = "gopeed_env";
      description = ''
        SOPS secret holding GOPEED_PASSWORD and GOPEED_APITOKEN. Without a
        password Gopeed serves the UI with no authentication at all.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Extensions run third-party JS with your hoster logins, so keep it off root.
    users.users.gopeed = {
      isSystemUser = true;
      group = "download";
      home = stateDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.downloadDir} 2770 gopeed download -"
    ];

    systemd.services.gopeed = {
      description = "Gopeed download manager";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = {
        GOPEED_USERNAME = cfg.username;
        GOPEED_DOWNLOADCONFIG = builtins.toJSON { downloadDir = cfg.downloadDir; };
      };

      serviceConfig = {
        User = "gopeed";
        Group = "download";
        UMask = "0002";
        StateDirectory = "gopeed";
        WorkingDirectory = stateDir;
        EnvironmentFile = config.sops.secrets.${cfg.environmentSecret}.path;
        ExecStart = "${lib.getExe package} -A 0.0.0.0 -P ${toString cfg.port} -d ${stateDir}";
        Restart = "on-failure";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_NETLINK"
        ];
        ReadWritePaths = [
          "/mnt/downloadHDD"
          "/mnt/downloadSSD"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
