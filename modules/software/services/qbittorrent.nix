{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.qbittorrent;

  privatePort = cfg.portSecret != null;
  portFile = config.sops.secrets.${cfg.portSecret}.path;

  hasPassword = cfg.webuiPasswordSecret != null;
  passwordFile = config.sops.secrets.${cfg.webuiPasswordSecret}.path;

  profileDir = "/var/lib/qBittorrent";
  configDir = "${profileDir}/qBittorrent/config";
  configFile = "${configDir}/qBittorrent.conf";

  # Tuning presets. Keys map straight onto `Session\<Key>` in qBittorrent.conf;
  # a host overrides individual keys through my.services.qbittorrent.tuning.
  profileTuning = {
    # Intake: churny, HDD-backed, queue on so a burst cannot thrash the disk.
    gen = {
      QueueingSystemEnabled = true;
      MaxActiveDownloads = 8;
      MaxActiveUploads = 10;
      MaxActiveTorrents = 20;
      IgnoreSlowTorrentsForQueueing = true;

      MaxConnections = 800;
      MaxConnectionsPerTorrent = 150;
      MaxUploads = 30;
      MaxUploadsPerTorrent = 6;

      FilePoolSize = 500;
      AsyncIOThreadsCount = 10;
      HashingThreadsCount = 2;
      CheckingMemUsageSize = 128;
      DiskQueueSize = 8388608;

      DHTEnabled = true;
      PeXEnabled = true;
      LSDEnabled = true;
    };

    # Long-term seeding: many small files, SSD-backed, nothing ever queued or removed.
    lts = {
      QueueingSystemEnabled = false;

      GlobalMaxRatio = "-1";
      GlobalMaxSeedingMinutes = -1;

      MaxConnections = 3000;
      MaxConnectionsPerTorrent = 60;
      MaxUploads = 200;
      MaxUploadsPerTorrent = 12;

      # FilePoolSize is the headline knob: upstream defaults to 100 open handles,
      # which thrashes against a library of many-small-file album torrents.
      FilePoolSize = 5000;
      AsyncIOThreadsCount = 32;
      HashingThreadsCount = 6;
      CheckingMemUsageSize = 512;
      DiskQueueSize = 16777216;
      SendBufferWatermark = 3000;
      SocketBacklogSize = 300;
      ConnectionSpeed = 100;

      DHTEnabled = false;
      PeXEnabled = false;
      LSDEnabled = false;
    };
  };

  sessionTuning = profileTuning.${cfg.profile} // cfg.tuning;

  baseServerConfig = {
    LegalNotice.Accepted = true;

    # qBittorrent 5 stamps this after running its config migrations. The config
    # is reinstalled from the store on every start, so pin it or migrations
    # re-run each boot against an already-current file.
    Meta.MigrationVersion = 8;

    Preferences = {
      General.Locale = "en";
      WebUI = {
        Address = "*";
        Port = cfg.webuiPort;
        Username = cfg.webuiUsername;
        LocalHostAuth = false;
        ClickjackingProtection = true;
        UseUPnP = false;
        SessionTimeout = 3600;
        MaxAuthenticationFailCount = 5;
        BanDuration = 3600;
        HostHeaderValidation = cfg.serverDomains != [ ];
        AuthSubnetWhitelistEnabled = cfg.authSubnetWhitelist != [ ];
      }
      // lib.optionalAttrs (cfg.authSubnetWhitelist != [ ]) {
        AuthSubnetWhitelist = lib.concatStringsSep ", " cfg.authSubnetWhitelist;
      }
      // lib.optionalAttrs (cfg.serverDomains != [ ]) {
        # Split on ";" by qBittorrent, unlike AuthSubnetWhitelist which is a QStringList.
        ServerDomains = lib.concatStringsSep ";" cfg.serverDomains;
      }
      // lib.optionalAttrs hasPassword {
        # Replaced from SOPS at pre-start; never the real hash in the store.
        Password_PBKDF2 = "@ByteArray(PLACEHOLDER)";
      };
    };

    # UPnP and NAT-PMP must stay off: the only reachable port is the one the VPN
    # gateway forwards, and probing for others leaks intent.
    Network.PortForwardingEnabled = false;

    BitTorrent.Session = {
      # Session\Port is deliberately absent. QBT_TORRENTING_PORT supplies it so
      # the forwarded port never reaches the Nix store.
      #
      # Interface/InterfaceName stay empty: the WireGuard tunnel terminates on the
      # gateway container, so binding to a wg device here would match nothing.
      Interface = "";
      InterfaceName = "";

      Encryption = 0;
      AnonymousMode = false;
      Preallocation = false;
      TorrentContentLayout = "Original";
      DefaultSavePath = cfg.defaultSavePath;
      TempPathEnabled = cfg.tempPath != null;
      GlobalUPSpeedLimit = cfg.uploadLimit;
      GlobalDLSpeedLimit = cfg.downloadLimit;
      DisableAutoTMMByDefault = !cfg.autoTMM;
    }
    // lib.optionalAttrs (cfg.tempPath != null) { TempPath = cfg.tempPath; }
    // sessionTuning;
  };

  serverConfig = lib.recursiveUpdate baseServerConfig cfg.extraServerConfig;

  categoriesJson = pkgs.writeText "qbittorrent-categories.json" (
    builtins.toJSON (lib.mapAttrs (_: category: { save_path = category.savePath; }) cfg.categories)
  );

  installCategories = pkgs.writeShellScript "qbittorrent-install-categories" ''
    set -eu
    ${pkgs.coreutils}/bin/install -Dm600 ${categoriesJson} ${configDir}/categories.json
  '';

  # The PBKDF2 hash is credential-equivalent, so it is substituted into the
  # installed config at runtime rather than rendered into the store. The key is
  # nested under Preferences.WebUI, so the rendered line is prefixed "WebUI\".
  injectPassword = pkgs.writeShellScript "qbittorrent-inject-password" ''
    set -eu
    hash=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg passwordFile})
    if ! ${pkgs.gnugrep}/bin/grep -q '^WebUI.Password_PBKDF2=' ${configFile}; then
      echo "qBittorrent config has no Password_PBKDF2 line to replace" >&2
      exit 1
    fi
    ${pkgs.gnused}/bin/sed -i \
      "s|^WebUI.Password_PBKDF2=.*|WebUI\\\\Password_PBKDF2=$hash|" \
      ${configFile}
  '';
in
{
  options.my.services.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent with declarative configuration";

    profile = lib.mkOption {
      type = lib.types.enum [
        "gen"
        "lts"
      ];
      description = "Tuning preset: gen for intake and downloads, lts for long-term seeding.";
    };

    portSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SOPS secret holding the forwarded listening port, read at runtime.";
    };

    webuiPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the qBittorrent web UI.";
    };

    webuiUsername = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Web UI account name.";
    };

    webuiPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SOPS secret holding the Password_PBKDF2 value, substituted at pre-start.";
    };

    authSubnetWhitelist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "10.73.73.13/32" ];
      description = "CIDRs allowed to reach the web UI without authenticating.";
    };

    serverDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Host headers accepted by the web UI. Empty disables host header validation.

        Rendered as a plain INI string, where ";" begins a comment, so entries
        past the first are silently dropped. Keep this to one name. Requests by
        IP are matched against the local address before this list is consulted,
        so they need no entry.
      '';
    };

    defaultSavePath = lib.mkOption {
      type = lib.types.str;
      description = "Save path used when a torrent arrives without one.";
    };

    tempPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Incomplete-download staging path. Null keeps data in place.";
    };

    autoTMM = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Automatic Torrent Management relocates data to category save paths.";
    };

    uploadLimit = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Global upload limit in KiB/s. 0 is unlimited.";
    };

    downloadLimit = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Global download limit in KiB/s. 0 is unlimited.";
    };

    categories = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.savePath = lib.mkOption {
            type = lib.types.str;
            description = "Save path for torrents in this category.";
          };
        }
      );
      default = { };
      description = "Categories written to categories.json, which serverConfig cannot express.";
    };

    tuning = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.either lib.types.str (lib.types.either lib.types.int lib.types.bool)
      );
      default = { };
      example = {
        FilePoolSize = 8000;
      };
      description = "Overrides merged over the profile preset, keyed by Session\\<Key> name.";
    };

    extraServerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Escape hatch merged over the generated serverConfig.";
    };

    readWritePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Data directories the service must be able to write to.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !privatePort || !config.networking.nftables.enable;
        message = "qBittorrent private-port firewall rules require the iptables firewall backend.";
      }
    ];

    services.qbittorrent = {
      enable = true;
      user = "root";
      group = "root";
      inherit profileDir;
      # Both must stay null: command-line arguments take precedence over the
      # QBT_* environment variables, and the port arrives via the environment.
      webuiPort = null;
      torrentingPort = null;
      extraArgs = [ "--confirm-legal-notice" ];
      inherit serverConfig;
    };

    sops.templates = lib.mkIf privatePort {
      "qbittorrent-port.env" = {
        content = "QBT_TORRENTING_PORT=${config.sops.placeholder.${cfg.portSecret}}";
        mode = "0400";
        restartUnits = [ "qbittorrent.service" ];
      };
    };

    systemd.services.qbittorrent = {
      after = lib.optionals privatePort [ "sops-install-secrets.service" ];
      restartTriggers = [ categoriesJson ];
      requires = lib.optionals (privatePort && config.sops.useSystemdActivation) [
        "sops-install-secrets.service"
      ];

      serviceConfig = {
        # Upstream targets a dedicated unprivileged user. These containers share
        # idmap-shifted bind mounts owned root:download, so a nested user
        # namespace would strip the supplementary group and lose write access.
        PrivateUsers = lib.mkForce false;
        ProtectHome = lib.mkForce false;
        SupplementaryGroups = "download";
        UMask = "007";
        Restart = "on-failure";
        # Must exceed FilePoolSize; the NixOS default soft limit is 1024.
        LimitNOFILE = 524288;
        ReadWritePaths = cfg.readWritePaths ++ [ profileDir ];

        EnvironmentFile = lib.mkIf privatePort config.sops.templates."qbittorrent-port.env".path;

        ExecStartPre = lib.mkAfter ([ installCategories ] ++ lib.optional hasPassword injectPassword);
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.webuiPort ];

    networking.firewall.extraCommands = lib.optionalString privatePort ''
      port=$(cat ${lib.escapeShellArg portFile})
      if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
        echo "Invalid qBittorrent forwarded-port secret" >&2
        exit 1
      fi
      iptables -A nixos-fw -p tcp --dport "$port" -j nixos-fw-accept
      iptables -A nixos-fw -p udp --dport "$port" -j nixos-fw-accept
    '';

    systemd.services.firewall = lib.mkIf privatePort {
      after = [ "sops-install-secrets.service" ];
      requires = lib.optionals config.sops.useSystemdActivation [ "sops-install-secrets.service" ];
    };
  };
}
