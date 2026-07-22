{ pkgs, ... }:

let
  core = "${pkgs.libretro.mupen64plus}/lib/retroarch/cores/mupen64plus_next_libretro.so";
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "N64";
      basePath = "n64/${file}";
      runner.emulator = {
        type = "retroarch";
        inherit core;
      };
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "worldIsNotEnoughN64" "world-is-not-enough-n64" "007: The World Is Not Enough (N64)"
      "007 - The World is Not Enough (U) [!].z64"
    )
    (mkGame "banjoKazooieN64" "banjo-kazooie-n64" "Banjo-Kazooie (N64)" "Banjo-Kazooie (U) [!].z64")
    (mkGame "californiaSpeedN64" "california-speed-n64" "California Speed (N64)"
      "California Speed (U) [!].z64"
    )
    (mkGame "carmageddon64N64" "carmageddon-64-n64" "Carmageddon 64 (N64)" "Carmageddon 64 (U) [!].z64")
    (mkGame "castlevaniaLegacyOfDarknessN64" "castlevania-legacy-of-darkness-n64"
      "Castlevania: Legacy of Darkness (N64)"
      "Castlevania - Legacy of Darkness (U) [!].z64"
    )
    (mkGame "castlevaniaN64" "castlevania-n64" "Castlevania (N64)" "Castlevania (U) [!].z64")
    (mkGame "commandAndConquerN64" "command-and-conquer-n64" "Command & Conquer (N64)"
      "Command & Conquer (U) [!].z64"
    )
    (mkGame "conkersBadFurDayN64" "conkers-bad-fur-day-n64" "Conker's Bad Fur Day (N64)"
      "Conker's Bad Fur Day (U) [!].z64"
    )
    (mkGame "cruisnExoticaN64" "cruisn-exotica-n64" "Cruis'n Exotica (N64)"
      "Cruis'n Exotica (U) [!].z64"
    )
    (mkGame "cruisnUsaN64" "cruisn-usa-n64" "Cruis'n USA (N64)" "Cruis'n USA (U) [!].z64")
    (mkGame "cruisnWorldN64" "cruisn-world-n64" "Cruis'n World (N64)" "Cruis'n World (U) [!].z64")
    (mkGame "donkeyKong64N64" "donkey-kong-64-n64" "Donkey Kong 64 (N64)" "Donkey Kong 64 (U) [!].z64")
    (mkGame "doom64N64" "doom-64-n64" "Doom 64 (N64)" "Doom 64 (U) [!].z64")
    (mkGame "dukeNukem64N64" "duke-nukem-64-n64" "Duke Nukem 64 (N64)" "Duke Nukem 64 (U) [!].z64")
    (mkGame "dukeNukemZeroHourN64" "duke-nukem-zero-hour-n64" "Duke Nukem: Zero Hour (N64)"
      "Duke Nukem - ZER0 H0UR (U) [!].z64"
    )
    (mkGame "frogger2N64" "frogger-2-n64" "Frogger 2 (N64)" "Frogger 2 (U) [!].z64")
    (mkGame "fZeroXN64" "f-zero-x-n64" "F-Zero X (N64)" "F-ZERO X (U) [!].z64")
    (mkGame "gex3DeepCoverGeckoN64" "gex-3-deep-cover-gecko-n64" "Gex 3: Deep Cover Gecko (N64)"
      "Gex 3 - Deep Cover Gecko (U) [!].z64"
    )
    (mkGame "gex64N64" "gex-64-n64" "Gex 64: Enter the Gecko (N64)"
      "Gex 64 - Enter the Gecko (U) [!].z64"
    )
    (mkGame "goldenEye007N64" "goldeneye-007-n64" "GoldenEye 007 (N64)" "GoldenEye 007 (U) [!].z64")
    (mkGame "kirby64N64" "kirby-64-n64" "Kirby 64: The Crystal Shards (N64)"
      "Kirby 64 - The Crystal Shards (U) [!].z64"
    )
    (mkGame "zeldaMajorasMaskN64" "zelda-majoras-mask-n64" "The Legend of Zelda: Majora's Mask (N64)"
      "Legend of Zelda, The - Majora's Mask (U) [!].z64"
    )
    (mkGame "zeldaOcarinaOfTimeMasterQuestN64" "zelda-ocarina-of-time-master-quest-n64"
      "The Legend of Zelda: Ocarina of Time Master Quest (N64)"
      "Legend of Zelda, The - Ocarina of Time - Master Quest (U) [!].z64"
    )
    (mkGame "zeldaOcarinaOfTimeN64" "zelda-ocarina-of-time-n64"
      "The Legend of Zelda: Ocarina of Time (N64)"
      "Legend of Zelda, The - Ocarina of Time (U) [!].z64"
    )
    (mkGame "marioGolfN64" "mario-golf-n64" "Mario Golf (N64)" "Mario Golf (U) [!].z64")
    (mkGame "marioKart64N64" "mario-kart-64-n64" "Mario Kart 64 (N64)" "Mario Kart 64 (U) [!].z64")
    (mkGame "marioParty2N64" "mario-party-2-n64" "Mario Party 2 (N64)" "Mario Party 2 (U) [!].z64")
    (mkGame "marioParty3N64" "mario-party-3-n64" "Mario Party 3 (N64)" "Mario Party 3 (U) [!].z64")
    (mkGame "marioTennisN64" "mario-tennis-n64" "Mario Tennis (N64)" "Mario Tennis (U) [!].z64")
    (mkGame "monopolyN64" "monopoly-n64" "Monopoly (N64)" "Monopoly (U) [!].z64")
    (mkGame "mortalKombat4N64" "mortal-kombat-4-n64" "Mortal Kombat 4 (N64)"
      "Mortal Kombat 4 (U) [!].z64"
    )
    (mkGame "mortalKombatMythologiesSubZeroN64" "mortal-kombat-mythologies-sub-zero-n64"
      "Mortal Kombat Mythologies: Sub-Zero (N64)"
      "Mortal Kombat Mythologies - Sub-Zero (U) [!].z64"
    )
    (mkGame "mortalKombatTrilogyN64" "mortal-kombat-trilogy-n64" "Mortal Kombat Trilogy (N64)"
      "Mortal Kombat Trilogy (U) [!].z64"
    )
    (mkGame "paperboyN64" "paperboy-n64" "Paperboy (N64)" "Paperboy (U) [!].z64")
    (mkGame "paperMarioN64" "paper-mario-n64" "Paper Mario (N64)" "Paper Mario (U) [!].z64")
    (mkGame "perfectDarkN64" "perfect-dark-n64" "Perfect Dark (N64)" "Perfect Dark (U) [!].z64")
    (mkGame "pokemonPuzzleLeagueN64" "pokemon-puzzle-league-n64" "Pokemon Puzzle League (N64)"
      "Pokemon Puzzle League (U) [!].z64"
    )
    (mkGame "pokemonSnapStationN64" "pokemon-snap-station-n64" "Pokemon Snap Station (N64)"
      "Pokemon Snap Station (U) [!].z64"
    )
    (mkGame "pokemonSnapN64" "pokemon-snap-n64" "Pokemon Snap (N64)" "Pokemon Snap (U) [!].z64")
    (mkGame "pokemonStadium2N64" "pokemon-stadium-2-n64" "Pokemon Stadium 2 (N64)"
      "Pokemon Stadium 2 (U) [!].z64"
    )
    (mkGame "pokemonStadiumN64" "pokemon-stadium-n64" "Pokemon Stadium (N64)"
      "Pokemon Stadium (U) [!].z64"
    )
    (mkGame "quake64N64" "quake-64-n64" "Quake 64 (N64)" "Quake 64 (U) [!].z64")
    (mkGame "quakeIIN64" "quake-ii-n64" "Quake II (N64)" "Quake II (U) [!].z64")
    (mkGame "rampage2UniversalTourN64" "rampage-2-universal-tour-n64" "Rampage 2: Universal Tour (N64)"
      "Rampage 2 - Universal Tour (U) [!].z64"
    )
    (mkGame "rampageWorldTourN64" "rampage-world-tour-n64" "Rampage: World Tour (N64)"
      "Rampage - World Tour (U) [!].z64"
    )
    (mkGame "starFox64N64" "star-fox-64-n64" "Star Fox 64 (N64)" "Star Fox 64 (U) [!].z64")
    (mkGame "superMario64N64" "super-mario-64-n64" "Super Mario 64 (N64)" "Super Mario 64 (U) [!].z64")
    (mkGame "superSmashBrosN64" "super-smash-bros-n64" "Super Smash Bros. (N64)"
      "Super Smash Bros. (U) [!].z64"
    )
    (mkGame "tonyHawksProSkater2N64" "tony-hawks-pro-skater-2-n64" "Tony Hawk's Pro Skater 2 (N64)"
      "Tony Hawk's Pro Skater 2 (U) [!].z64"
    )
    (mkGame "tonyHawksProSkater3N64" "tony-hawks-pro-skater-3-n64" "Tony Hawk's Pro Skater 3 (N64)"
      "Tony Hawk's Pro Skater 3 (U).z64"
    )
    (mkGame "tonyHawksProSkaterN64" "tony-hawks-pro-skater-n64" "Tony Hawk's Pro Skater (N64)"
      "Tony Hawk's Pro Skater (U) [!].z64"
    )
    (mkGame "waveRace64N64" "wave-race-64-n64" "Wave Race 64 (N64)" "Wave Race 64 (U) [!].z64")
    (mkGame "yoshisStoryN64" "yoshis-story-n64" "Yoshi's Story (N64)" "Yoshi's Story (U) [!].z64")
  ];
}
