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
      (rpcs3.overrideAttrs (prev: {
        cmakeFlags = prev.cmakeFlags ++ [ (lib.cmakeBool "BUILD_SHARED_LIBS" false) ];
      })) # PS3
      pcsx2 # PS2
      ryubing # Switch
    ];
  };
}
