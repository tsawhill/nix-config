{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  hyprlandPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.hyprland.nixosModules.default ];

  options = {
    desktop.hyprland.enable = lib.mkEnableOption "Hyprland wayland compositor";
    my.hypr.launcher = lib.mkOption {
      type = lib.types.enum [
        "walker"
        "none"
      ];
      default = "walker";
      description = "Application launcher to use with Hyprland.";
    };
  };

  config = lib.mkIf config.desktop.hyprland.enable {
    nix.settings = {
      extra-substituters = [
        "https://walker.cachix.org"
        "https://walker-git.cachix.org"
      ];
      extra-trusted-public-keys = [
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      ];
    };

    programs.hyprland = {
      enable = true;
      package = hyprlandPkgs.hyprland;
      portalPackage = hyprlandPkgs.xdg-desktop-portal-hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };

    # GTK portal needed alongside hyprland's own portal for file pickers etc.
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    environment.systemPackages = with pkgs; [
      grimblast
      libnotify
      wl-clipboard
      hyprlock
      hyprcursor
      hyprpolkitagent
    ];
  };
}
