{ config, lib, pkgs, ... }:
let
  cfg = config.my.hypr;
  p = cfg.monitors.primary;
  s = cfg.monitors.secondary;

  # Workspace 1-5 live on monitor A, 6-10 on monitor B. Emitted as Lua
  # (hl.workspace_rule) since it is dofile'd from the Lua config.
  mkRules = A: B: (
    ''
      hl.workspace_rule({ workspace = "1", monitor = "${A}", default = true })
      hl.workspace_rule({ workspace = "2", monitor = "${A}" })
      hl.workspace_rule({ workspace = "3", monitor = "${A}" })
      hl.workspace_rule({ workspace = "4", monitor = "${A}" })
      hl.workspace_rule({ workspace = "5", monitor = "${A}" })
    '' + lib.optionalString (B != null) ''
      hl.workspace_rule({ workspace = "6", monitor = "${B}", default = true })
      hl.workspace_rule({ workspace = "7", monitor = "${B}" })
      hl.workspace_rule({ workspace = "8", monitor = "${B}" })
      hl.workspace_rule({ workspace = "9", monitor = "${B}" })
      hl.workspace_rule({ workspace = "10", monitor = "${B}" })
    ''
  );

  defaultRules = pkgs.writeText "hypr-workspace-rules-default.lua" (
    lib.optionalString (p != "") (mkRules p s)
  );

  swappedRules = pkgs.writeText "hypr-workspace-rules-swapped.lua" (
    lib.optionalString (p != "" && s != null) (mkRules s p)
  );

  rulesPath = "${config.home.homeDirectory}/.config/hypr/workspace-rules.lua";
  stateFile = "${config.home.homeDirectory}/.local/state/hypr-swap-state";
  primaryMonitorFile = "${config.home.homeDirectory}/.local/state/hypr-primary-monitor";

  # Runs on every Hyprland start. Restores workspace/monitor mapping based on
  # the persisted swap state, reloads config, and points X primary output at
  # the monitor currently hosting workspaces 1-5 (where Steam lives).
  initScript = pkgs.writeShellScript "hypr-init-workspace-rules" (
    if s == null then ''
      mkdir -p "$(dirname ${rulesPath})" "$(dirname ${primaryMonitorFile})"
      cp ${defaultRules} "${rulesPath}"
      printf '%s\n' "${p}" > "${primaryMonitorFile}"
      hyprctl reload config-only
      ${lib.getExe pkgs.xrandr} --output "${p}" --primary 2>/dev/null || true
    '' else ''
      mkdir -p "$(dirname ${stateFile})" "$(dirname ${rulesPath})" "$(dirname ${primaryMonitorFile})"
      if [ -f "${stateFile}" ]; then
        cp ${swappedRules} "${rulesPath}"
        XRANDR_PRIMARY="${s}"
      else
        cp ${defaultRules} "${rulesPath}"
        XRANDR_PRIMARY="${p}"
      fi
      printf '%s\n' "$XRANDR_PRIMARY" > "${primaryMonitorFile}"
      hyprctl reload config-only
      ${lib.getExe pkgs.xrandr} --output "$XRANDR_PRIMARY" --primary 2>/dev/null || true
    ''
  );
in
lib.mkIf (p != "") {
  # Seed rules file on home-manager activation so Hyprland's `source` directive
  # has something to read at session start. Respects persisted swap state.
  home.activation.initHyprWorkspaceRules = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    ''
      mkdir -p "$HOME/.config/hypr"
      mkdir -p "$HOME/.local/state"
    '' + (if s == null then ''
      cp ${defaultRules} "$HOME/.config/hypr/workspace-rules.conf"
      printf '%s\n' "${p}" > "$HOME/.local/state/hypr-primary-monitor"
    '' else ''
      if [ -f "$HOME/.local/state/hypr-swap-state" ]; then
        cp ${swappedRules} "$HOME/.config/hypr/workspace-rules.conf"
        printf '%s\n' "${s}" > "$HOME/.local/state/hypr-primary-monitor"
      else
        cp ${defaultRules} "$HOME/.config/hypr/workspace-rules.conf"
        printf '%s\n' "${p}" > "$HOME/.local/state/hypr-primary-monitor"
      fi
    '')
  );

  # Load the mutable workspace-rules Lua file (seeded on activation and at start
  # by initScript), then run initScript which re-seeds per swap state + reloads.
  wayland.windowManager.hyprland.extraConfig = ''
    do
      local wsRules = "${rulesPath}"
      local f = io.open(wsRules, "r")
      if f then
        f:close()
        dofile(wsRules)
      end
    end

    hl.on("hyprland.start", function()
      hl.exec_cmd("${initScript}")
    end)
  '';
}
