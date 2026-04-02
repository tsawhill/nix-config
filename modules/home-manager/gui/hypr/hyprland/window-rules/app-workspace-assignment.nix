{
  # NOTE FOR DEVELOPERS:
  # Workspace numbers correspond to monitor layout defined in workspaces.nix:
  #   Primary monitor   → workspaces 1–5
  #   Secondary monitor → workspaces 6–10
  # "silent" means the window opens on the workspace without switching to it.
  wayland.windowManager.hyprland.settings.windowrule = [
    # --- Development (primary, ws 3) ---
    "match:class codium, workspace 3 silent"
    "workspace 3 silent,match:class insomnia"

    # --- Gaming (primary, ws 4–5) ---
    "workspace 4 silent,match:class Steam"
    "workspace 4 silent,match:class steam"
    "workspace 5 silent,match:class gamescope"
    "workspace 5 silent,match:class .gamescope-wrapped"
    "workspace 2 silent,match:class cs2"

    # --- Secondary monitor apps (ws 6) ---
    "workspace 6 silent,match:class vesktop"
    "workspace 6 silent,match:class feishin"
    "workspace 6 silent,match:class com.obsproject.Studio"
  ];
}
