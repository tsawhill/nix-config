{
  imports = [
    ./input.nix
    ./autostart.nix
    ./appearance.nix
    ./bindings.nix
    ./workspaces.nix
    ./window-rules
  ];
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false; # Using uwsm so disable -- https://wiki.hyprland.org/Useful-Utilities/Systemd-start/
    package = null; # Installed with nixos module from flake
    portalPackage = null; # Installed with the nixos module from flake
    settings = {
      env = [
        "GDK_SCALE, 1"
        "ELECTRON_OZONE_PLATFORM_HINT,wayland"
        "MANGOHUD, 1"
        "EDITOR, nvim"
      ];

      # Default monitor for newly plugged in displays
      monitor = [ " , preferred, auto, 1.5" ];

      misc = {
        disable_hyprland_logo = true;
        enable_swallow = true;
        swallow_regex = "^(foot)$";
      };
      general = {
        layout = "dwindle";
        allow_tearing = true;
      };
      dwindle = {
        pseudotile = "yes";
        preserve_split = "yes";
        force_split = 2;
      };
      "$mainMod" = "SUPER";
    };
  };
}
