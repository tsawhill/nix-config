{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.qbit-manage;

  # The rendered template is root-only under /run. qbit-manage rewrites its own
  # config across schema migrations, so it runs against a writable copy.
  runtimeConfig = "/run/qbit-manage/config.yml";

  # Tracker keywords identify which private trackers are in use, so they come
  # from SOPS. Group names and limits stay in the repo where they can be reviewed.
  trackerSection =
    lib.mapAttrs' (
      tag: secret: lib.nameValuePair config.sops.placeholder.${secret} { inherit tag; }
    ) cfg.trackerSecrets
    // {
      other.tag = "other";
    };

  # YAML is a superset of JSON and qbit-manage parses with PyYAML, so JSON is a
  # valid config and the structure stays a real Nix attrset.
  configContent = builtins.toJSON {
    commands = {
      dry_run = cfg.dryRun;
      # tag_update applies the tracker section's tags; share_limits then filters
      # on those tags. Without it the groups match nothing.
      tag_update = true;
      share_limits = true;
      cat_update = false;
      recheck = false;
      rem_unregistered = false;
      tag_tracker_error = false;
      rem_orphaned = false;
      tag_nohardlinks = false;
      skip_cleanup = true;
      # qbit-manage 4.7.1 caps at qBittorrent 5.2.0 and nixpkgs ships 5.2.2.
      # The gap is a patch release against Web API 2.15.1, so the check is
      # skipped rather than pinning qBittorrent back. Revisit on a major bump.
      skip_qb_version_check = true;
    };

    qbt = {
      # 127.0.0.1, not localhost: validateHostHeader matches the Host against the
      # local address before consulting ServerDomains, so the literal IP passes
      # where the name would be rejected.
      host = "127.0.0.1:${toString cfg.qbittorrentPort}";
      user = "";
      pass = "";
    };

    settings = {
      # Must stay false: forcing AutoTMM would relocate adopted seed data.
      force_auto_tmm = false;
      tracker_error_tag = "issue";
      nohardlinks_tag = "noHL";
      share_limits_tag = "~share_limit";
      share_limits_filter_completed = true;
      disable_qbt_default_share_limits = true;
    };

    directory = {
      root_dir = cfg.rootDir;
      recycle_bin = cfg.recycleBin.path;
      torrents_dir = cfg.torrentsDir;
    };

    # cleanup moves torrents here rather than erasing them, giving a recovery
    # window. save_torrents keeps the .torrent alongside the data, which matters
    # because those files are the only copy of their passkeys.
    recyclebin = {
      enabled = cfg.recycleBin.enable;
      empty_after_x_days = cfg.recycleBin.emptyAfterDays;
      save_torrents = true;
      split_by_category = false;
    };

    cat = cfg.categories;
    tracker = trackerSection;
    share_limits = cfg.shareLimits;
  };
in
{
  options.my.services.qbit-manage = {
    enable = lib.mkEnableOption "qbit-manage, for per-tracker share limits";

    qbittorrentPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Local qBittorrent web UI port. Reached over loopback, where LocalHostAuth is off.";
    };

    rootDir = lib.mkOption {
      type = lib.types.str;
      description = "Torrent data root. Only used by the orphaned and nohardlinks commands, which are off.";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Report what would change without applying it. Leave on until the output is boring.";
    };

    torrentsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qBittorrent/qBittorrent/data/BT_backup";
      description = "qBittorrent's BT_backup directory. Required for the recycle bin to save .torrent files.";
    };

    recycleBin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Move cleaned-up torrents here instead of deleting outright.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/downloadHDD/.RecycleBin";
        description = "Recycle bin location. Same filesystem as the data avoids a copy on move.";
      };

      emptyAfterDays = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "How long recovered-from-cleanup data survives before real deletion.";
      };
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the run timer.";
    };

    trackerSecrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        t1 = "qbit_tracker_t1";
      };
      description = "Map of tag name to the SOPS secret holding that tracker's announce-URL keyword.";
    };

    categories = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Mandatory cat section: category name to save path. Unused while cat_update is off.";
    };

    shareLimits = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Share limit groups, keyed by group name. Lowest priority wins and each
        torrent takes the first group it matches. Keep cleanup false: this holds
        torrents whose .torrent files are the only copy of their passkeys.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.qbit-manage ];

    sops.templates."qbit-manage.yml" = {
      content = configContent;
      mode = "0400";
    };

    systemd.services.qbit-manage = {
      description = "qbit-manage share limit run";
      after = [
        "qbittorrent.service"
        "sops-install-secrets.service"
      ];
      requires = lib.optionals config.sops.useSystemdActivation [ "sops-install-secrets.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RuntimeDirectory = "qbit-manage";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = "${pkgs.coreutils}/bin/install -m600 ${
          config.sops.templates."qbit-manage.yml".path
        } ${runtimeConfig}";
        # --web-server=False is required: the server defaults to ON for non-Docker
        # runs and keeps the process alive, so a Type=oneshot unit would sit in
        # "activating" forever and block its own timer. --run then exits cleanly.
        ExecStart = "${pkgs.qbit-manage}/bin/qbit-manage --config-file ${runtimeConfig} --run --web-server=False";
      };
    };

    systemd.timers.qbit-manage = {
      description = "Periodic qbit-manage share limit run";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };
}
