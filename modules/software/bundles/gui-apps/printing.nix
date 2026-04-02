{ pkgs, lib, config, ... }:
{
  options.software.apps.printing.enable = lib.mkEnableOption "3D printing and modeling tools";

  config = lib.mkIf config.software.apps.printing.enable {
    environment.systemPackages = with pkgs; [
      orca-slicer
      freecad
      blender
    ];
  };
}
