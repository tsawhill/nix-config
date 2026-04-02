{ lib, config, ... }:
{
  options.my.udev.hidraw.enable = lib.mkEnableOption "hidraw access for plugdev group" // {
    default = true;
  };

  config = lib.mkIf config.my.udev.hidraw.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", GROUP="plugdev", MODE="0660"
    '';
  };
}
