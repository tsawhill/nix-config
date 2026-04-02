{ config, lib, pkgs, ... }:
let
  cfg = config.my.hypr;
  p = cfg.monitors.primary;
  s = cfg.monitors.secondary;

  # Default workspace rules written to a mutable file that Hyprland sources.
  # The swap script rewrites this file and reloads config to move all workspaces.
  defaultRules = pkgs.writeText "hypr-workspace-rules-default.conf" (
    lib.optionalString (p != "") (
      ''
        workspace = 1, monitor:${p}, default:true
        workspace = 2, monitor:${p}
        workspace = 3, monitor:${p}
        workspace = 4, monitor:${p}
        workspace = 5, monitor:${p}
      '' + lib.optionalString (s != null) ''
        workspace = 6, monitor:${s}, default:true
        workspace = 7, monitor:${s}
        workspace = 8, monitor:${s}
        workspace = 9, monitor:${s}
        workspace = 10, monitor:${s}
      ''
    )
  );

  rulesPath = "${config.home.homeDirectory}/.config/hypr/workspace-rules.conf";
in
lib.mkIf (p != "") {
  # Create the rules file on first activation (ensures it exists before Hyprland starts).
  home.activation.initHyprWorkspaceRules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.config/hypr/workspace-rules.conf" ]; then
      cp ${defaultRules} "$HOME/.config/hypr/workspace-rules.conf"
    fi
  '';

  # Reset rules to default on every Hyprland start, then reload so they take effect.
  wayland.windowManager.hyprland.settings.exec-once = [
    "cp ${defaultRules} ${rulesPath} && hyprctl reload config-only"
  ];

  # Source the mutable rules file from the Hyprland config.
  wayland.windowManager.hyprland.extraConfig = ''
    source = ${rulesPath}
  '';
}
