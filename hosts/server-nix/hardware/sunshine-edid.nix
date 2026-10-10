{ pkgs, ... }:

let
  sunshineEdid =
    pkgs.runCommand "sunshine-dummy-plug.edid"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${./edid/mk-sunshine-edid.py} ${./edid/dummy-plug.bin} $out
      '';
in
{
  # The NVIDIA DRM driver only accepts modes from the pool it derives from a
  # connector's EDID, so the custom modes KWin adds inside sunshine-nix fail the
  # atomic check with EINVAL ("The driver rejected the display configuration").
  # nvidia-drm exposes no EDID parameter, but it does honour the DRM core's
  # debugfs override, so hand the connector an EDID that already lists the
  # modes. drm_kms_helper.edid_firmware would be tidier but is unverified here.
  systemd.services.sunshine-edid = {
    description = "Override the Sunshine dummy plug EDID";
    wantedBy = [ "multi-user.target" ];
    after = [
      "sys-kernel-debug.mount"
      "systemd-modules-load.service"
    ];
    # An unprivileged guest receives no udev hotplug events, so KWin reads the
    # connector only when it starts. The override must already be in place.
    before = [ "incus-startup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      override=""
      for _ in $(seq 1 120); do
        for candidate in /sys/kernel/debug/dri/*/HDMI-A-1/edid_override; do
          if [ -e "$candidate" ]; then
            override="$candidate"
          fi
        done
        if [ -n "$override" ]; then
          break
        fi
        sleep 0.5
      done

      if [ -z "$override" ]; then
        echo "No HDMI-A-1 DRM connector appeared" >&2
        exit 1
      fi

      # Only the dummy plug (EDID name 28E850, or SUNSHINE once overridden) gets the
      # override; a real monitor on this port keeps its own modes.
      dummy=false
      for edid in /sys/class/drm/*-HDMI-A-1/edid; do
        if ${pkgs.gnugrep}/bin/grep -aq -e 28E850 -e SUNSHINE "$edid"; then
          dummy=true
        fi
      done
      if [ "$dummy" = false ]; then
        echo "HDMI-A-1 is not the Sunshine dummy plug; leaving its EDID alone"
        exit 0
      fi

      ${pkgs.coreutils}/bin/cat ${sunshineEdid} > "$override"

      # The connector was already probed while the driver loaded, so the new
      # EDID only reaches the mode pool after a forced re-detect.
      for status in /sys/class/drm/*-HDMI-A-1/status; do
        if [ -w "$status" ]; then
          echo detect > "$status"
        fi
      done
    '';
  };
}
