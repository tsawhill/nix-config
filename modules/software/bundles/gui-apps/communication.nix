{ pkgs, lib, config, ... }:
let
  cfg = config.software.apps.communication;
in
{
  options.software.apps.communication = {
    enable = lib.mkEnableOption "communication apps";
  };

  config = lib.mkIf cfg.enable {
    software.apps.vesktop.enable = lib.mkDefault true;

    environment.systemPackages = [
      pkgs.thunderbird
    ];
  };
}
