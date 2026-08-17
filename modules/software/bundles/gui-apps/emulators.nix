{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.apps.emulators.enable = lib.mkEnableOption "game emulators";

  config = lib.mkIf config.software.apps.emulators.enable {
    # RPCS3 still uses AVCodec fields removed in FFmpeg 8, so it stays on the
    # last compatible release. PCSX2 has migrated: nixpkgs now asks it for
    # ffmpeg_8 by name, so overriding `ffmpeg` there fails to evaluate.
    nixpkgs.overlays = [
      (
        _final: prev:
        let
          rpcs3Ffmpeg7 = prev.rpcs3.override { ffmpeg = prev.ffmpeg_7; };
        in
        {
          # RPCS3 links FFmpeg 7, while Qt Multimedia's default FFmpeg backend
          # links the current FFmpeg ABI. Loading both in one process crashes
          # when RPCS3 constructs its Qt music handler. The supported GStreamer
          # backend avoids that mixed-ABI process and works for both the GUI and
          # declarative game launchers.
          rpcs3 = prev.symlinkJoin {
            name = "${rpcs3Ffmpeg7.name}-gstreamer";
            paths = [ rpcs3Ffmpeg7 ];
            nativeBuildInputs = [ prev.makeWrapper ];
            postBuild = ''
              rm "$out/bin/rpcs3"
              makeWrapper ${lib.getExe rpcs3Ffmpeg7} "$out/bin/rpcs3" \
                --set QT_MEDIA_BACKEND gstreamer
            '';
            inherit (rpcs3Ffmpeg7) meta;
          };
        }
      )
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
