{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:

let
  # Vector's binary embeds the build's cc path, dragging ~300 MiB of gcc and
  # binutils into every host. Copy it with that string blanked instead.
  vectorSlim =
    pkgs.runCommand "vector-${pkgs.vector.version}-slim"
      {
        nativeBuildInputs = [ pkgs.removeReferencesTo ];
        meta.mainProgram = "vector";
      }
      ''
        cp -r --no-preserve=mode ${pkgs.vector} $out
        chmod +x $out/bin/vector
        for cc in $(grep -aoE '/nix/store/[a-z0-9]{32}-gcc-wrapper-[^/]+' $out/bin/vector | sort -u); do
          remove-references-to -t "$cc" $out/bin/vector
        done
      '';
  cfg = config.my.monitoring.logs;
  agent = cfg.agent;
  stack = cfg.stack;
  lanDomain = networkTopology.domains.lan;
  # Matches the short `instance` label Prometheus uses, so dashboards can
  # join metrics and logs on the same host name.
  host = config.networking.hostName;
  hasFiles = agent.files != [ ];
  lokiDir = "/var/lib/loki";
in
{
  options.my.monitoring.logs = {
    agent = {
      enable = lib.mkEnableOption "Vector log shipping to the central Loki";

      lokiUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://monitoring-nix.${lanDomain}:3100";
        description = "Loki base URL; Vector appends the push path itself.";
      };

      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "/var/log/nginx/*.log" ];
        description = "Log file globs to tail in addition to the journal.";
      };

      fileGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "nginx" ];
        description = "Groups Vector joins so it can read those files.";
      };
    };

    stack = {
      enable = lib.mkEnableOption "central Loki log store";

      retention = lib.mkOption {
        type = lib.types.str;
        default = "30d";
        description = "How long Loki keeps logs.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf agent.enable {
      services.vector = {
        enable = true;
        package = vectorSlim;
        journaldAccess = true;
        settings = {
          data_dir = "/var/lib/vector";
          sources = {
            journal = {
              type = "journald";
              # Start from now on first run so a fleet deploy doesn't backfill
              # every host's journal at once; restarts resume from the checkpoint.
              since_now = true;
            };
          }
          // lib.optionalAttrs hasFiles {
            files = {
              type = "file";
              include = agent.files;
            };
          };

          transforms.journal_labels = {
            type = "remap";
            inputs = [ "journal" ];
            source = ''
              unit = string(._SYSTEMD_UNIT) ?? string(.SYSLOG_IDENTIFIER) ?? "unknown"
              # Collapse instance names so sshd@<conn>.service and session-N.scope share one stream.
              unit = replace(unit, r'@.*\.', "@.")
              .unit = replace(unit, r'^session-[^.]+\.scope$', "session.scope")
              priority = to_int(.PRIORITY) ?? 6
              .level = to_syslog_level(priority) ?? "info"
              msg = string(.message) ?? ""
              # JSON loggers write everything at journal priority info; use their own level instead.
              if starts_with(msg, "{") {
                fields = object(parse_json(msg) ?? null) ?? {}
                lvl = downcase(string(fields.level) ?? "")
                levels = {"trace": "debug", "debug": "debug", "info": "info", "warn": "warning", "warning": "warning", "error": "err", "err": "err", "critical": "crit", "crit": "crit", "fatal": "crit", "panic": "emerg"}
                .level = string(get(levels, [lvl]) ?? null) ?? .level
              }
              # Aborting drops the event: debug noise, per-path GC deletions, and passing Gatus checks.
              if .level == "debug" { abort }
              if .unit == "nix-gc.service" && starts_with(msg, "deleting '/nix/store/") { abort }
              if .unit == "gatus.service" && contains(msg, "success=true") { abort }
            '';
          };

          sinks = {
            loki_journal = {
              type = "loki";
              inputs = [ "journal_labels" ];
              endpoint = agent.lokiUrl;
              encoding.codec = "text";
              labels = {
                inherit host;
                unit = "{{ unit }}";
                level = "{{ level }}";
              };
              out_of_order_action = "accept";
            };
          }
          // lib.optionalAttrs hasFiles {
            # Separate sink so the journal label templates never fail on file events.
            loki_files = {
              type = "loki";
              inputs = [ "files" ];
              endpoint = agent.lokiUrl;
              encoding.codec = "text";
              labels = {
                inherit host;
                filename = "{{ file }}";
              };
              out_of_order_action = "accept";
            };
          };
        };
      };

      systemd.services.vector.serviceConfig.SupplementaryGroups = agent.fileGroups;
    })

    (lib.mkIf stack.enable {
      services.loki = {
        enable = true;
        configuration = {
          auth_enabled = false;
          server = {
            http_listen_address = "0.0.0.0";
            http_listen_port = 3100;
            # Info logs every query and flush, and those land back in Loki.
            log_level = "warn";
          };
          common = {
            path_prefix = lokiDir;
            storage.filesystem = {
              chunks_directory = "${lokiDir}/chunks";
              rules_directory = "${lokiDir}/rules";
            };
            replication_factor = 1;
            ring = {
              instance_addr = "127.0.0.1";
              kvstore.store = "inmemory";
            };
          };
          schema_config.configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
          limits_config = {
            retention_period = stack.retention;
            # Grafana's Logs Drilldown groups by service_name; use the unit or file.
            discover_service_name = [
              "unit"
              "filename"
            ];
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
          };
          # Retention is a no-op unless the compactor enforces it.
          compactor = {
            working_directory = "${lokiDir}/compactor";
            retention_enabled = true;
            delete_request_store = "filesystem";
            compaction_interval = "10m";
          };
          analytics.reporting_enabled = false;
        };
      };

      services.grafana.provision.datasources.settings.datasources = [
        {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:3100";
          uid = "loki";
        }
      ];

      networking.firewall.allowedTCPPorts = [ 3100 ];
    })
  ];
}
