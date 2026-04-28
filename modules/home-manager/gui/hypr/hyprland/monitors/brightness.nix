{
  lib,
  config,
  pkgs,
  ...
}:
let
  brightnessScript = pkgs.writeShellScript "hypr-brightness" ''
    DIR="$HOME/.config/hypr/monitors"
    STEP=0.10
    MIN=0.10
    MAX=1.00

    direction="$1"

    for f in "$DIR"/*.conf; do
      [ -f "$f" ] || continue
      current=$(${pkgs.gnugrep}/bin/grep -oP 'sdr_brightness = \K[0-9.]+' "$f")
      current=''${current:-1.00}

      if [ "$direction" = "up" ]; then
        new=$(${pkgs.gawk}/bin/awk "BEGIN {v=$current+$STEP; if(v>$MAX) v=$MAX; printf \"%.2f\", v}")
      else
        new=$(${pkgs.gawk}/bin/awk "BEGIN {v=$current-$STEP; if(v<$MIN) v=$MIN; printf \"%.2f\", v}")
      fi

      ${pkgs.gnused}/bin/sed -i "s/sdr_brightness = [0-9.]*/sdr_brightness = $new/" "$f"
    done

    ${pkgs.hyprland}/bin/hyprctl reload
    pct=$(${pkgs.gawk}/bin/awk "BEGIN {printf \"%d\", $new * 100}")
    ${pkgs.libnotify}/bin/notify-send -t 1500 -u low -h "int:value:$pct" "Brightness" "''${pct}%"
  '';
in
{
  wayland.windowManager.hyprland.settings.binde = [
    "$mainMod ALT, up, exec, ${brightnessScript} up"
    "$mainMod ALT, down, exec, ${brightnessScript} down"
  ];
}
