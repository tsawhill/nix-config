{
  config,
  lib,
  networkTopology,
  pkgs,
  ...
}:

let
  repoPath = "/mnt/zpool/code/nix-config";
  flakePath = "path://${repoPath}";
  deployLockPath = "/run/lock/colmena-deploy.lock";
  retryStateDir = "/var/lib/colmena-deploy-retries";
  notifications = config.my.monitoring.notifications;
  incusGuests = lib.mapAttrs (name: host: {
    instance = name;
    manager = networkTopology.lib.fqdn host.incus.manager;
    intermittent = host.incus.intermittent or false;
  }) (lib.filterAttrs (_: host: host ? incus) networkTopology.hosts);

  # Nix owns site-specific data; the Rust controller owns deployment behavior.
  deployctlConfig = (pkgs.formats.json { }).generate "deployctl.json" {
    repo_path = repoPath;
    flake_uri = flakePath;
    retry_state_dir = retryStateDir;
    retry_gcroot_dir = "/nix/var/nix/gcroots/colmena-retries";
    built_gcroot_dir = "/nix/var/nix/gcroots/colmena-hosts";
    deploy_lock_path = deployLockPath;
    system_profile = "/nix/var/nix/profiles/system";
    lan_domain = networkTopology.domains.lan;
    per_host_build_timeout = "6h";
    apply_timeout = "90m";
    incus_boot_timeout_secs = 180;
    # Physical and remote hosts retain two closures for offline comparisons.
    # Reproducible Incus guests retain only their newest built closure; their
    # own system profile remains the source of truth for activation rollback.
    keep_roots = 2;
    incus_keep_roots = 1;
    incus_guests = incusGuests;
    notifications = {
      gotify_url = notifications.gotify.url;
      gotify_token_file = notifications.gotify.tokenFile;
      recipient_email = notifications.recipientEmail;
    };
    # Deploy summaries run on the LAN Ollama box. Every failure here degrades
    # to a mechanical summary rather than failing the deploy.
    summary = {
      enabled = true;
      endpoint = "http://${networkTopology.lib.fqdn "llm-nix"}:11434/api/chat";
      model = "qwen2.5-coder:7b";
      keep_alive = "5m";
      # Ollama otherwise defaults to 4k and silently drops the rest of the
      # prompt, which would cut the closure diff off mid-list.
      num_ctx = 16384;
      temperature = 0.2;
      max_tokens = 400;
      request_timeout_secs = 240;
      max_closure_lines = 60;
      max_diff_chars = 12000;
      marker_ref = "refs/deployctl/last-deploy";
    };
    # Physical hosts may be asleep. LXC containers do not need Wake-on-LAN.
    wol_macs = {
      taylor-desktop-nix = "c8:7f:54:6c:e2:96";
      # taylor-laptop-nix = "aa:bb:cc:dd:ee:ff";
      # pi-backup-nix = "aa:bb:cc:dd:ee:ff";
    };
  };

  deployctlRaw = pkgs.callPackage ../../../../pkgs/deployctl { };
  runtimePath = lib.makeBinPath [
    pkgs.colmena
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.hostname
    pkgs.msmtp
    pkgs.nix
    pkgs.openssh
    pkgs.wol
  ];
  deployctl = pkgs.symlinkJoin {
    name = "deployctl-wrapped";
    paths = [ deployctlRaw ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/deployctl" \
        --set DEPLOYCTL_CONFIG ${deployctlConfig} \
        --prefix PATH : ${runtimePath}
    '';
  };

  # Preserve the small commands used over SSH and in shell aliases.
  deploy = pkgs.writeShellScriptBin "deploy" ''
    exec ${deployctl}/bin/deployctl deploy "$@"
  '';
  deployOld = pkgs.writeShellScriptBin "deploy-old" ''
    exec ${deployctl}/bin/deployctl rollback "$@"
  '';
  deployRetry = pkgs.writeShellScriptBin "deploy-retry" ''
    exec ${deployctl}/bin/deployctl retry "$@"
  '';
  deploySummary = pkgs.writeShellScriptBin "deploy-summary" ''
    exec ${deployctl}/bin/deployctl summary "$@"
  '';

  mkDeployService = name: selector: {
    description = "${name} Colmena Deploy";
    restartIfChanged = false;
    stopIfChanged = false;
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sops-nix.service"
      "flake-update.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${deployctl}/bin/deployctl scheduled ${name} ${selector}";
    };
  };

  mkTimer = name: onCalendar: {
    enable = true;
    description = "Run ${name} Colmena Deploy";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = onCalendar;
      Persistent = true;
      Unit = "deploy-${name}.service";
    };
  };
in
{
  environment.systemPackages = [
    deployctl
    deploy
    deployOld
    deployRetry
    deploySummary
  ];

  systemd.tmpfiles.rules = [
    "d ${retryStateDir} 0700 root root -"
  ];

  systemd.services = {
    flake-update = {
      description = "Update nix flake inputs";
      restartIfChanged = false;
      stopIfChanged = false;
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.coreutils
        pkgs.git
        pkgs.nix
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -euo pipefail
        exec 9>${deployLockPath}
        if ! flock -n 9; then
          echo "[$(date -Is)] Another deploy is running; waiting to update flake inputs"
          flock 9
        fi
        echo "[$(date -Is)] Updating flake inputs"
        cd ${repoPath}
        nix flake update --flake ${flakePath}
        git add flake.lock
        git commit -m "auto: flake update $(date '+%Y-%m-%d %H:%M')" || true
      '';
    };

    "deploy-Daily" = mkDeployService "Daily" "@daily";
    "deploy-Weekly" = mkDeployService "Weekly" "@daily,@weekly";
    "deploy-Monthly" = mkDeployService "Monthly" "@daily,@weekly,@monthly";

    deploy-retry = {
      description = "Retry deferred Colmena deploys";
      restartIfChanged = false;
      stopIfChanged = false;
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${deployctl}/bin/deployctl retry";
      };
    };
  };

  systemd.timers = {
    flake-update = {
      enable = true;
      description = "Update nix flake inputs daily before the fleet deploy";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 23:00:00";
        Persistent = true;
        Unit = "flake-update.service";
      };
    };

    # These calendars are mutually exclusive. Saturday jobs include every
    # shorter cadence, so each host is built and deployed only once that night.
    "deploy-Daily" = mkTimer "Daily" [
      "Sun *-*-* 00:00"
      "Mon..Fri *-*-* 00:00"
    ];
    "deploy-Weekly" = mkTimer "Weekly" "Sat *-*-8..31 00:00";
    "deploy-Monthly" = mkTimer "Monthly" "Sat *-*-1..7 00:00";
    deploy-retry = {
      enable = true;
      description = "Retry deferred Colmena deploys every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Offset off the hour so scheduled deploys take the lock first.
        OnCalendar = "*-*-* *:02/5:00";
        Persistent = true;
        Unit = "deploy-retry.service";
      };
    };
  };
}
