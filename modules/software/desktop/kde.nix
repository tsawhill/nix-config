{ pkgs, lib, config, ... }:
{
  options.desktop.kde.enable = lib.mkEnableOption "KDE Plasma desktop environment";

  config = lib.mkIf config.desktop.kde.enable {
    services.xserver.enable = true;

    services.desktopManager.plasma6.enable = true;

    # Remove default KDE bloat
    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      elisa
      khelpcenter
      plasma-browser-integration
    ];

    environment.systemPackages = with pkgs.kdePackages; [
      kcalc
      kate
    ];
  };
}
