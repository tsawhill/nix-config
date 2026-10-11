{
  config,
  pkgs,
  ...
}:
let
  metricsDirectory = "/var/lib/prometheus-node-exporter-text-files";
in
{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
  };

  # Incus has the cgroup-attributed guest metrics that /proc-based collectors
  # cannot provide from inside an LXC. Publish a local snapshot through the
  # existing node_exporter textfile collector; no Incus TCP endpoint or client
  # certificate is needed.
  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=${metricsDirectory}" ];
  };
  systemd.tmpfiles.rules = [ "d ${metricsDirectory} 0755 root root -" ];
  systemd.services.incus-metrics-textfile = {
    description = "Export Incus instance metrics for Prometheus node_exporter";
    after = [ "incus.service" ];
    requires = [ "incus.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 '${metricsDirectory}'
      metrics_tmp="$(${pkgs.coreutils}/bin/mktemp '${metricsDirectory}/incus.prom.XXXXXX')"
      trap '${pkgs.coreutils}/bin/rm -f "$metrics_tmp"' EXIT
      if ! ${config.virtualisation.incus.package}/bin/incus query /1.0/metrics > "$metrics_tmp"; then
        ${pkgs.coreutils}/bin/rm -f '${metricsDirectory}/incus.prom'
        exit 1
      fi
      ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp"
      ${pkgs.coreutils}/bin/mv "$metrics_tmp" '${metricsDirectory}/incus.prom'
      trap - EXIT
    '';
  };
  systemd.timers.incus-metrics-textfile = {
    description = "Refresh Incus instance metrics for Prometheus";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      Unit = "incus-metrics-textfile.service";
    };
  };
  # The rebuild runner lives in the build-nix container on this Incus host.
  # Do not let a server-nix switch restart Incus out from under that deploy.
  systemd.services.incus = {
    restartIfChanged = false;
    stopIfChanged = false;
  };
  system.activationScripts.scheduleIncusRestartAfterSwitch = {
    text = ''
      if [ "''${NIXOS_ACTION:-}" = switch ] || [ "''${NIXOS_ACTION:-}" = test ]; then
        old_unit=/run/current-system/etc/systemd/system/incus.service
        new_unit="$systemConfig/etc/systemd/system/incus.service"

        if [ -e "$old_unit" ] \
          && [ -e "$new_unit" ] \
          && ! ${pkgs.diffutils}/bin/cmp -s "$old_unit" "$new_unit" \
          && ${pkgs.systemd}/bin/systemctl --quiet is-active incus.service; then
          echo "incus.service changed; scheduling delayed restart after activation"
          ${pkgs.systemd}/bin/systemctl stop \
            incus-restart-after-activation.timer \
            incus-restart-after-activation.service \
            >/dev/null 2>&1 || true
          if ! ${pkgs.systemd}/bin/systemd-run \
            --unit=incus-restart-after-activation \
            --description="Restart Incus after NixOS activation" \
            --on-active=15min \
            --property=Type=oneshot \
            --collect \
            ${pkgs.systemd}/bin/systemctl try-restart incus.service; then
            echo "warning: failed to schedule delayed incus.service restart" >&2
          fi
        fi
      fi
    '';
  };
  networking = {
    nftables.enable = true;
    firewall.allowedTCPPorts = [
      8443
    ];
  };
  users.users.taylor.extraGroups = [ "incus-admin" ];
}
