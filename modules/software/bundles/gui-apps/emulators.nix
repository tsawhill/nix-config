{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.apps.emulators.enable = lib.mkEnableOption "game emulators";

  config = lib.mkIf config.software.apps.emulators.enable {
    environment.systemPackages = with pkgs; [
      retroarch
      dolphin-emu # GameCube / Wii
      rpcs3 # PS3
      pcsx2 # PS2
      ryubing # Switch
    ];
  };
}
