{ pkgs, ... }:
{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
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
            --on-active=5min \
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
