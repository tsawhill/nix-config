{ pkgs, ... }:

let
  core = "${pkgs.libretro.melondsds}/lib/retroarch/cores/melondsds_libretro.so";
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "Nintendo DS";
      basePath = "nds/${file}";
      runner.emulator = {
        type = "retroarch";
        inherit core;
      };
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "coryInTheHouseNds" "cory-in-the-house-nds" "Cory in the House (DS)"
      "Cory in the House (USA).zip"
    )
    (mkGame "newSuperMarioBrosNds" "new-super-mario-bros-nds" "New Super Mario Bros. (DS)"
      "New Super Mario Bros. (USA, Australia).zip"
    )
    (mkGame "pokemonHeartGoldNds" "pokemon-heartgold-nds" "Pokemon HeartGold Version (DS)"
      "Pokémon HeartGold Version (USA).zip"
    )
    (mkGame "pokemonPlatinumNds" "pokemon-platinum-nds" "Pokemon Platinum Version (DS)"
      "Pokémon Platinum Version (USA) (Rev 1).zip"
    )
    (mkGame "superMario64Ds" "super-mario-64-ds" "Super Mario 64 DS" "Super Mario 64 DS (USA).zip")
  ];
}
