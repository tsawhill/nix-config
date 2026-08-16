{ pkgs, ... }:
let
  # sysfs attrs, so udev MODE/GROUP (device nodes only) does not apply.
  ledPerms = pkgs.writeShellScript "valve-leds-perms" ''
    for f in /sys/class/leds/"$1"/*; do
      [ -f "$f" ] || continue
      ${pkgs.coreutils}/bin/chgrp video "$f" 2>/dev/null || true
      ${pkgs.coreutils}/bin/chmod g+w "$f" 2>/dev/null || true
    done
  '';

  # Steam's brightness slider writes brightness_scale, a global EC register that
  # this box ignores: setting it to 0 leaves the LEDs at full. Per-LED brightness
  # does work, because led_mc_calc_color_components turns it into a multiplier on
  # the RGB registers. So mirror the slider onto all 17 LEDs.
  brightnessMirror = pkgs.writeShellScript "valve-leds-brightness-mirror" ''
    scale='/sys/class/leds/valve-leds[0]/brightness_scale'
    prev=
    while :; do
      if [ -r "$scale" ]; then
        read -r cur < "$scale" || cur=
        if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
          # brightness_scale reads as hex (0xff); brightness takes 0-255.
          val=$(( cur ))
          for i in $(seq 0 16); do
            printf '%s' "$val" > "/sys/class/leds/valve-leds[$i]/brightness" 2>/dev/null || true
          done
          prev=$cur
        fi
      fi
      sleep 0.2
    done
  '';
in
{
  # The valve-leds driver binds fine, but its attrs are root-owned 644, so the
  # gamescope session cannot drive the light bar. taylor is already in video.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="valve-leds*", RUN+="${ledPerms} %k"
  '';

  systemd.services.valve-leds-brightness-mirror = {
    description = "Mirror Steam's LED brightness slider onto per-LED brightness";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/devices/platform/valve-leds";
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStart = brightnessMirror;
      Restart = "always";
      RestartSec = 5;
    };
  };
}
