{ lib, config, ... }:
{
  options.my.udev.hidraw.enable = lib.mkEnableOption "hidraw access for input group" // {
    default = true;
  };

  config = lib.mkIf config.my.udev.hidraw.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", GROUP="input", MODE="0660", TAG+="uaccess"
    '';
  };
}
