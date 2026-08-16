{ pkgs, ... }:
let
  # cec_notifier_get_conn() matches an unnamed lookup against any notifier for
  # the device, but a named lookup only against an identical name. amdgpu
  # registers unnamed; cros_ec_cec looks up "Port C" from its DMI table. So
  # whichever probes first decides:
  #
  #   cros_ec_cec first -> "Port C" exists, amdgpu wildcards onto it   -> works
  #   amdgpu first      -> unnamed exists, cros_ec_cec cannot match it -> orphan
  #
  # CEC_CROS_EC is a module loaded from udev, while early modesetting puts
  # amdgpu in the initrd, so amdgpu wins and the adapter sits at f.f.f.f.
  # Re-registering amdgpu's notifier once cros_ec_cec is up lands it on the
  # right one.
  #
  # Wait on /dev/cec0 rather than the EC's cec_phys_addr: the EC keeps that
  # value across a warm reboot, so it goes stale-valid and is no signal that the
  # link is right. cros_ec_cec_init_port() registers the notifier before
  # cec_register_adapter(), so the node existing means "Port C" is there to
  # match. Then re-register unconditionally; it is cheap and safe to repeat.
  cecFixup = pkgs.writeShellScript "cec-notifier-fixup" ''
    set -u
    modprobe cros_ec_cec 2>/dev/null || true

    node=""
    for _ in $(seq 1 30); do
      if [ -e /dev/cec0 ]; then
        node=$(find /sys/kernel/debug/dri -name hdmi_cec_state 2>/dev/null | head -1)
        [ -n "$node" ] && break
      fi
      sleep 1
    done

    if [ -z "$node" ]; then
      echo "no cec adapter or hdmi_cec_state node; nothing to do"
      exit 0
    fi

    # Logged so the journal shows whether the softdep below already won the race
    # on its own, in which case this service is redundant.
    before=$(cec-ctl -d /dev/cec0 2>/dev/null | sed -n 's/.*Physical Address *: *//p' | head -1)
    echo "adapter physical address before re-register: ''${before:-unknown}"

    echo "re-registering amdgpu CEC notifier via $node"
    echo 0 > "$node"; sleep 1
    echo 1 > "$node"; sleep 1

    after=$(cec-ctl -d /dev/cec0 2>/dev/null | sed -n 's/.*Physical Address *: *//p' | head -1)
    echo "adapter physical address after re-register: ''${after:-unknown}"
    echo "EC reports: $(cat /sys/class/chromeos/cros_ec/cec_phys_addr)"
  '';
in
{
  systemd.services.cec-notifier-fixup = {
    description = "Bind the cros-ec CEC adapter to amdgpu's notifier";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-kernel-debug.mount" ];
    requires = [ "sys-kernel-debug.mount" ];
    path = [
      pkgs.kmod
      pkgs.coreutils
      pkgs.findutils
      pkgs.v4l-utils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = cecFixup;
    };
  };

  # The notifier link is lost if the connector is re-probed across a sleep.
  powerManagement.resumeCommands = "${cecFixup}";

  # Try to win the race properly rather than repairing it after the fact: load
  # cros_ec_cec before amdgpu so it registers "Port C" first. Unproven, because
  # load order is not probe order -- cros_ec_cec cannot register its notifier
  # until the EC's MFD has created cros-ec-cec.2.auto -- and early KMS loads
  # amdgpu from the initrd, where this config may not apply. If the service log
  # shows a valid address before re-registering, this worked and the service can
  # go.
  boot.extraModprobeConfig = "softdep amdgpu pre: cros_ec_cec";
}
