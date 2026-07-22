{ pkgs, ... }:

let
  core = "${pkgs.libretro.citra}/lib/retroarch/cores/citra_libretro.so";
in
{
  software.games.entries.superMario3DLand3ds = {
    command = "super-mario-3d-land-3ds";
    desktopName = "Super Mario 3D Land (3DS)";
    category = "Nintendo 3DS";
    basePath = "3ds/Super Mario 3D Land (U).3ds";
    runner.emulator = {
      type = "retroarch";
      inherit core;
    };
  };
}
