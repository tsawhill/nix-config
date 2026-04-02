{ pkgs, lib, config, ... }:
{
  options.software.apps.tools.enable = lib.mkEnableOption "desktop utility apps";

  config = lib.mkIf config.software.apps.tools.enable {
    environment.systemPackages = with pkgs; [
      # Disk management
      gparted

      # File management
      nemo-with-extensions
      filezilla

      # Downloading
      deluge-gtk
      pyload-ng

      # Music / tuning
      lingot

      # Finance
      monero-gui
    ];
  };
}
