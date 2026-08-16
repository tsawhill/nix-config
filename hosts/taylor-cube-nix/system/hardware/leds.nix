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
in
{
  # The valve-leds driver binds fine, but its attrs are root-owned 644, so the
  # gamescope session cannot drive the light bar. taylor is already in video.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="valve-leds*", RUN+="${ledPerms} %k"
  '';
}
