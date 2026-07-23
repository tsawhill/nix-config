{
  config,
  lib,
  pkgs,
  ...
}:
# Dynamically assigns workspaces 6-10 to a secondary monitor when one is
# connected, and moves them back to primary when it is disconnected.
# Only active when monitors.secondary is null (i.e. secondary is not a fixed,
# known monitor — typically laptops). Desktops with a fixed secondary use
# static workspace rules in workspaces.nix instead.
let
  cfg = config.my.hypr;
  p = cfg.monitors.primary;

  # At runtime: use the configured primary name if known, otherwise detect it.
  primaryCmd =
    if p != "" then
      "echo '${p}'"
    else
      ''hyprctl monitors -j | ${lib.getExe pkgs.jq} -r '[.[] | select(.name | startswith("HEADLESS") | not)] | .[0].name' '';

  daemonScript = pkgs.writeShellScriptBin "hypr-monitor-workspaces" ''
    handle() {
      EVENT="''${1%%>>*}"
      DATA="''${1#*>>}"
      case "$EVENT" in
        monitoradded)
          [[ "$DATA" == HEADLESS* ]] && return
          for i in 6 7 8 9 10; do
            hyprctl dispatch wsbind "$i $DATA"
            hyprctl dispatch moveworkspacetomonitor "$i $DATA"
          done
          ;;
        monitorremoved)
          P=$(${primaryCmd})
          [ -z "$P" ] && return
          for i in 6 7 8 9 10; do
            hyprctl dispatch wsbind "$i $P"
            hyprctl dispatch moveworkspacetomonitor "$i $P"
          done
          ;;
      esac
    }

    ${lib.getExe pkgs.socat} - \
      "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" \
      | while IFS= read -r line; do handle "$line"; done
  '';
in
lib.mkIf (cfg.monitors.secondary == null) {
  home.packages = [ daemonScript ];
  wayland.windowManager.hyprland.extraConfig = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd("${lib.getExe daemonScript}")
    end)
  '';
}
