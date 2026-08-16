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
  # right one. Idempotent: only acts when the address is still invalid.
  cecFixup = pkgs.writeShellScript "cec-notifier-fixup" ''
    set -u
    modprobe cros_ec_cec 2>/dev/null || true

    addr=""
    for _ in $(seq 1 30); do
      addr=$(cat /sys/class/chromeos/cros_ec/cec_phys_addr 2>/dev/null || true)
      [ -n "$addr" ] && break
      sleep 1
    done

    if [ -z "$addr" ]; then
      echo "no cros_ec cec_phys_addr; nothing to do"
      exit 0
    fi

    # "<port> <addr>", 65535 (0xffff) meaning unset.
    case "$addr" in
      *" 65535") ;;
      *) echo "physical address already set ($addr)"; exit 0 ;;
    esac

    node=$(find /sys/kernel/debug/dri -name hdmi_cec_state 2>/dev/null | head -1)
    if [ -z "$node" ]; then
      echo "no hdmi_cec_state node; is the HDMI connector present?"
      exit 0
    fi

    echo "re-registering amdgpu CEC notifier via $node"
    echo 0 > "$node"; sleep 1
    echo 1 > "$node"; sleep 1
    echo "physical address now: $(cat /sys/class/chromeos/cros_ec/cec_phys_addr)"
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
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = cecFixup;
    };
  };

  # The notifier link is lost if the connector is re-probed across a sleep.
  powerManagement.resumeCommands = "${cecFixup}";
}
