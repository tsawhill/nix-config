{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.my.desktop.autoLoginUser = lib.mkOption {
    type = lib.types.str;
    default = "taylor";
    description = "User to automatically log in to the display manager.";
  };

  config = {
    services.libinput.enable = true;

    services.displayManager = {
      defaultSession = "hyprland-uwsm";
      sddm = {
        enable = true;
        wayland.enable = true;
        # Use the specific package for the Qt6 version of SDDM. mkDefault so a
        # host can enable desktop.kde alongside this dir: nixpkgs' plasma6.nix
        # sets this same package at normal priority, and two normal-priority
        # definitions are an eval error even when the derivation is identical.
        package = lib.mkDefault pkgs.kdePackages.sddm;

        # The theme name to use
        theme = "${pkgs.sddm-astronaut}/share/sddm/themes/sddm-astronaut-theme";

        # Essential Qt6 dependencies for themes to render correctly
        extraPackages = with pkgs.kdePackages; [
          qtmultimedia
          qtsvg
          qtvirtualkeyboard
        ];
      };

      autoLogin = {
        enable = true;
        user = config.my.desktop.autoLoginUser;
      };
    };
  };
}
