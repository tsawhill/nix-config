{ pkgs, lib, config, ... }:
{
  options.software.apps.communication.enable = lib.mkEnableOption "communication apps";

  config = lib.mkIf config.software.apps.communication.enable {
    environment.systemPackages = with pkgs; [
      vesktop
      thunderbird
      mailspring
    ];
  };
}
