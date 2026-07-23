{ config, lib, ... }:
{
  options.my.hypr.windowRules.appWorkspaceAssignment.enable = lib.mkEnableOption "app workspace assignment rules" // { default = true; };

  config = lib.mkIf config.my.hypr.windowRules.appWorkspaceAssignment.enable {
    # NOTE FOR DEVELOPERS:
    # Workspace numbers correspond to monitor layout defined in workspaces.nix:
    #   Primary monitor   → workspaces 1–5
    #   Secondary monitor → workspaces 6–10
    # "silent" means the window opens on the workspace without switching to it.
    wayland.windowManager.hyprland.settings.window_rule = [
      # --- Development (primary, ws 3) ---
      { match = { class = "codium"; }; workspace = "3 silent"; }
      { match = { class = "insomnia"; }; workspace = "3 silent"; }

      # --- Gaming (primary, ws 4–5) ---
      { match = { class = "Steam"; }; workspace = "4 silent"; }
      { match = { class = "steam"; }; workspace = "4 silent"; }
      { match = { class = "gamescope"; }; workspace = "5 silent"; }
      { match = { class = ".gamescope-wrapped"; }; workspace = "5 silent"; }
      { match = { class = "cs2"; }; workspace = "2 silent"; }

      # --- Secondary monitor apps (ws 6) ---
      { match = { class = "vesktop"; }; workspace = "6 silent"; }
      { match = { class = "feishin"; }; workspace = "6 silent"; }
      { match = { class = "com.obsproject.Studio"; }; workspace = "6 silent"; }
    ];
  };
}
