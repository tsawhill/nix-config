{
  config,
  lib,
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
in
lib.mkIf (cfg.monitors.secondary == null) {
  wayland.windowManager.hyprland.extraConfig = ''
    local function dynamicPrimaryMonitor()
      ${
        if p != "" then
          ''return "${p}"''
        else
          ''
            for _, monitor in ipairs(hl.get_monitors()) do
              if not monitor.name:match("^HEADLESS") then
                return monitor.name
              end
            end
            return nil
          ''
      }
    end

    local function placeSecondaryWorkspaces(monitorName)
      if not monitorName then
        return
      end

      for i = 6, 10 do
        hl.workspace_rule({ workspace = tostring(i), monitor = monitorName })
        hl.dispatch(hl.dsp.workspace.move({ workspace = i, monitor = monitorName }))
      end
    end

    hl.on("monitor.added", function(monitor)
      if not monitor.name:match("^HEADLESS") then
        placeSecondaryWorkspaces(monitor.name)
      end
    end)

    hl.on("monitor.removed", function(monitor)
      if not monitor.name:match("^HEADLESS") then
        placeSecondaryWorkspaces(dynamicPrimaryMonitor())
      end
    end)
  '';
}
