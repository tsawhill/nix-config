{ pkgs, ... }:

let
  core = "${pkgs.libretro.fceumm}/lib/retroarch/cores/fceumm_libretro.so";
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "NES";
      basePath = "nes/${file}";
      runner.emulator = {
        type = "retroarch";
        inherit core;
      };
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "superMarioBrosNes" "super-mario-bros-nes" "Super Mario Bros. (NES)"
      "Super Mario Bros. (World).nes"
    )
    (mkGame "superMarioBros2Nes" "super-mario-bros-2-nes" "Super Mario Bros. 2 (NES)"
      "Super Mario Bros. 2 (USA) (Rev 1).nes"
    )
    (mkGame "superMarioBros3Nes" "super-mario-bros-3-nes" "Super Mario Bros. 3 (NES)"
      "Super Mario Bros. 3 (USA) (Rev 1).nes"
    )
  ];
}
