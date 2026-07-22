{ pkgs, ... }:

let
  core = "${pkgs.libretro.snes9x}/lib/retroarch/cores/snes9x_libretro.so";
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "SNES";
      basePath = "snes/${file}";
      runner.emulator = {
        type = "retroarch";
        inherit core;
      };
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "donkeyKongCountrySnes" "donkey-kong-country-snes" "Donkey Kong Country (SNES)"
      "Donkey Kong Country (USA) (Rev 2).sfc"
    )
    (mkGame "donkeyKongCountry2Snes" "donkey-kong-country-2-snes"
      "Donkey Kong Country 2: Diddy's Kong Quest (SNES)"
      "Donkey Kong Country 2 - Diddy's Kong Quest (USA) (En,Fr) (Rev 1) (Virtual Console).sfc"
    )
    (mkGame "donkeyKongCountry3Snes" "donkey-kong-country-3-snes"
      "Donkey Kong Country 3: Dixie Kong's Double Trouble! (SNES)"
      "Donkey Kong Country 3 - Dixie Kong's Double Trouble! (USA) (En,Fr).sfc"
    )
    (mkGame "superMarioAllStarsSnes" "super-mario-all-stars-snes" "Super Mario All-Stars (SNES)"
      "Super Mario All-Stars (USA, Europe) (Switch Online).sfc"
    )
    (mkGame "superMarioRpgSnes" "super-mario-rpg-snes"
      "Super Mario RPG: Legend of the Seven Stars (SNES)"
      "Super Mario RPG - Legend of the Seven Stars (USA, Europe) (Virtual Console).sfc"
    )
    (mkGame "superMarioWorldSnes" "super-mario-world-snes" "Super Mario World (SNES)"
      "Super Mario World.sfc"
    )
    (mkGame "yoshisIslandSnes" "yoshis-island-snes" "Super Mario World 2: Yoshi's Island (SNES)"
      "Super Mario World 2 - Yoshi's Island (USA).sfc"
    )
  ];
}
