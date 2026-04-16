{ config, lib, pkgs, ... }:
let
  cfg = config.my.hypr;
  p = cfg.monitors.primary;
  s = cfg.monitors.secondary;

  # Workspace 1-5 live on monitor A, 6-10 on monitor B.
  mkRules = A: B: (
    ''
      workspace = 1, monitor:${A}, default:true
      workspace = 2, monitor:${A}
      workspace = 3, monitor:${A}
      workspace = 4, monitor:${A}
      workspace = 5, monitor:${A}
    '' + lib.optionalString (B != null) ''
      workspace = 6, monitor:${B}, default:true
      workspace = 7, monitor:${B}
      workspace = 8, monitor:${B}
      workspace = 9, monitor:${B}
      workspace = 10, monitor:${B}
    ''
  );

  defaultRules = pkgs.writeText "hypr-workspace-rules-default.conf" (
    lib.optionalString (p != "") (mkRules p s)
  );

  swappedRules = pkgs.writeText "hypr-workspace-rules-swapped.conf" (
    lib.optionalString (p != "" && s != null) (mkRules s p)
  );

  rulesPath = "${config.home.homeDirectory}/.config/hypr/workspace-rules.conf";
  stateFile = "${config.home.homeDirectory}/.local/state/hypr-swap-state";

  # Runs on every Hyprland start. Restores workspace/monitor mapping based on
  # the persisted swap state, reloads config, and points X primary output at
  # the monitor currently hosting workspaces 1-5 (where Steam lives).
  initScript = pkgs.writeShellScript "hypr-init-workspace-rules" (
    if s == null then ''
      mkdir -p "$(dirname ${rulesPath})"
      cp ${defaultRules} "${rulesPath}"
      hyprctl reload config-only
      ${pkgs.xorg.xrandr}/bin/xrandr --output "${p}" --primary 2>/dev/null || true
    '' else ''
      mkdir -p "$(dirname ${stateFile})" "$(dirname ${rulesPath})"
      if [ -f "${stateFile}" ]; then
        cp ${swappedRules} "${rulesPath}"
        XRANDR_PRIMARY="${s}"
      else
        cp ${defaultRules} "${rulesPath}"
        XRANDR_PRIMARY="${p}"
      fi
      hyprctl reload config-only
      ${pkgs.xorg.xrandr}/bin/xrandr --output "$XRANDR_PRIMARY" --primary 2>/dev/null || true
    ''
  );
in
lib.mkIf (p != "") {
  # Seed rules file on home-manager activation so Hyprland's `source` directive
  # has something to read at session start. Respects persisted swap state.
  home.activation.initHyprWorkspaceRules = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    ''
      mkdir -p "$HOME/.config/hypr"
    '' + (if s == null then ''
      cp ${defaultRules} "$HOME/.config/hypr/workspace-rules.conf"
    '' else ''
      mkdir -p "$HOME/.local/state"
      if [ -f "$HOME/.local/state/hypr-swap-state" ]; then
        cp ${swappedRules} "$HOME/.config/hypr/workspace-rules.conf"
      else
        cp ${defaultRules} "$HOME/.config/hypr/workspace-rules.conf"
      fi
    '')
  );

  wayland.windowManager.hyprland.settings.exec-once = [
    "${initScript}"
  ];

  # Source the mutable rules file from the Hyprland config.
  wayland.windowManager.hyprland.extraConfig = ''
    source = ${rulesPath}
  '';
}
