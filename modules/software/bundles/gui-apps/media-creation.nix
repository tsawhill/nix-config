{ pkgs, lib, config, ... }:
{
  options.software.apps.media-creation.enable = lib.mkEnableOption "media creation and editing apps";

  config = lib.mkIf config.software.apps.media-creation.enable {
    environment.systemPackages = with pkgs; [
      # Video editing
      davinci-resolve
      kdePackages.kdenlive

      # Image editing
      gimp
      krita

      # Audio editing
      audacity
      reaper
    ];
  };
}
