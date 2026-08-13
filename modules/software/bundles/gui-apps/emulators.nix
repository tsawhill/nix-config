{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.apps.emulators.enable = lib.mkEnableOption "game emulators";

  config = lib.mkIf config.software.apps.emulators.enable {
    # PCSX2 and RPCS3 still use AVCodec fields removed in FFmpeg 8. Keep only
    # these emulators on the last compatible FFmpeg release until they migrate.
    nixpkgs.overlays = [
      (_final: prev: {
        pcsx2 = prev.pcsx2.override { ffmpeg = prev.ffmpeg_7; };
        rpcs3 = prev.rpcs3.override { ffmpeg = prev.ffmpeg_7; };
      })
    ];

    environment.systemPackages = with pkgs; [
      retroarch
      dolphin-emu # GameCube / Wii
      rpcs3
      ps3-disc-dumper
      pcsx2 # PS2
      ryubing # Switch
    ];
  };
}
