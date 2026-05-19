{ config, lib, pkgs, ... }:
let
  cfg = config.my.hypr;

  swapScript = pkgs.writeShellScriptBin "hypr-swap-monitors" (
    ''
    REAL_MONITORS=$(hyprctl monitors -j | ${lib.getExe pkgs.jq} '[.[] | select(.name | startswith("HEADLESS") | not)]')

    # Abort if fewer than 2 real monitors are connected
    COUNT=$(echo "$REAL_MONITORS" | ${lib.getExe pkgs.jq} 'length')
    if [ "$COUNT" -lt 2 ]; then
      notify-send -t 2000 -u low "Swap Monitors" "Only one monitor connected"
      exit 0
    fi

    # Use configured primary if set, otherwise fall back to first real monitor at runtime
    if [ -n "${cfg.monitors.primary}" ]; then
      PRIMARY="${cfg.monitors.primary}"
    else
      PRIMARY=$(echo "$REAL_MONITORS" | ${lib.getExe pkgs.jq} -r '.[0].name')
    fi
    SECONDARY=$(echo "$REAL_MONITORS" | ${lib.getExe pkgs.jq} -r '[.[] | select(.name != "'"$PRIMARY"'")] | .[0].name')

    RULES_FILE="$HOME/.config/hypr/workspace-rules.conf"
    STATE_FILE="$HOME/.local/state/hypr-swap-state"
    PRIMARY_FILE="$HOME/.local/state/hypr-primary-monitor"
    mkdir -p "$(dirname "$STATE_FILE")"

    # Record what each monitor is currently showing before we move anything
    WS_ON_PRIMARY=$(echo "$REAL_MONITORS" | ${lib.getExe pkgs.jq} -r --arg m "$PRIMARY" '.[] | select(.name == $m) | .activeWorkspace.id')
    WS_ON_SECONDARY=$(echo "$REAL_MONITORS" | ${lib.getExe pkgs.jq} -r --arg m "$SECONDARY" '.[] | select(.name == $m) | .activeWorkspace.id')

    if [ -f "$STATE_FILE" ]; then
      A=$PRIMARY; B=$SECONDARY
      rm "$STATE_FILE"
    else
      A=$SECONDARY; B=$PRIMARY
      echo "swapped" > "$STATE_FILE"
    fi

    printf '%s\n' "$A" > "$PRIMARY_FILE"

    ''
    + lib.optionalString (cfg.gpuRecorder.enable && cfg.gpuRecorder.captureTarget == "primary") ''
    # Replay capture reads the primary monitor at service start.
    # Restart only the replay service so manual recordings are not interrupted.
    if ${pkgs.systemd}/bin/systemctl --user --quiet is-active gpu-recorder.service; then
      ${pkgs.systemd}/bin/systemctl --user restart gpu-recorder.service
    fi

    ''
    + ''
    # Update rules file so non-existent workspaces land on the right monitor after restart
    cat > "$RULES_FILE" << EOF
workspace = 1, monitor:$A, default:true
workspace = 2, monitor:$A
workspace = 3, monitor:$A
workspace = 4, monitor:$A
workspace = 5, monitor:$A
workspace = 6, monitor:$B, default:true
workspace = 7, monitor:$B
workspace = 8, monitor:$B
workspace = 9, monitor:$B
workspace = 10, monitor:$B
EOF

    # Move existing workspaces immediately (non-existent ones are silently skipped)
    for i in 1 2 3 4 5;  do hyprctl dispatch moveworkspacetomonitor "$i $A" 2>/dev/null; done
    for i in 6 7 8 9 10; do hyprctl dispatch moveworkspacetomonitor "$i $B" 2>/dev/null; done

    # Restore each monitor to the workspace it was showing before the swap
    hyprctl dispatch focusmonitor "$SECONDARY" && hyprctl dispatch workspace "$WS_ON_PRIMARY"
    hyprctl dispatch focusmonitor "$PRIMARY"   && hyprctl dispatch workspace "$WS_ON_SECONDARY"

    # Update X primary output so XWayland apps (Steam toasts) place popups on the correct monitor
    ${lib.getExe pkgs.xrandr} --output "$A" --primary 2>/dev/null || true

    ''
  );
in
{
  home.packages = [ swapScript ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mainMod, M, exec, hypr-swap-monitors"
  ];
}
