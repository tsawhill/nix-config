{ pkgs, ... }:

let
  core = "${pkgs.libretro.mame2003-plus}/lib/retroarch/cores/mame2003_plus_libretro.so";
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "Arcade";
      basePath = "arcade/${file}";
      runner.emulator = {
        type = "retroarch";
        inherit core;
      };
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "mortalKombatArcade" "mortal-kombat-arcade" "Mortal Kombat (Arcade)" "mk.zip")
    (mkGame "mortalKombatIIArcade" "mortal-kombat-ii-arcade" "Mortal Kombat II (Arcade)" "mk2.zip")
    (mkGame "mortalKombat3Arcade" "mortal-kombat-3-arcade" "Mortal Kombat 3 (Arcade)" "mk3.zip")
    (mkGame "ultimateMortalKombat3Arcade" "ultimate-mortal-kombat-3-arcade"
      "Ultimate Mortal Kombat 3 (Arcade)"
      "Ultimate Mortal Kombat 3.zip"
    )
  ];
}
