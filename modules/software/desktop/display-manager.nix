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
        # Use the specific package for the Qt6 version of SDDM.
        # mkDefault so hosts that also enable Plasma 6 (taylor-cube-nix) don't
        # collide — plasma6.nix sets this same kdePackages.sddm unconditionally,
        # so it wins there and the result is identical either way.
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
