let
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "Wii";
      basePath = "wii/${file}";
      runner.emulator.type = "dolphin";
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "marioKartWii" "mario-kart-wii" "Mario Kart Wii" "Mario Kart Wii (USA) (En,Fr,Es).rvz")
    (mkGame "marioParty8Wii" "mario-party-8-wii" "Mario Party 8 (Wii)"
      "Mario Party 8 (USA, Asia) (Rev 2).nkit.gcz"
    )
    (mkGame "newSuperMarioBrosWii" "new-super-mario-bros-wii" "New Super Mario Bros. Wii"
      "New Super Mario Bros. Wii (USA) (En,Fr,Es) (Rev 2).rvz"
    )
    (mkGame "superMarioGalaxyWii" "super-mario-galaxy-wii" "Super Mario Galaxy (Wii)"
      "Super Mario Galaxy (USA) (En,Fr,Es).rvz"
    )
    (mkGame "superMarioGalaxy2Wii" "super-mario-galaxy-2-wii" "Super Mario Galaxy 2 (Wii)"
      "Super Mario Galaxy 2 (USA) (En,Fr,Es).rvz"
    )
    (mkGame "wiiPlay" "wii-play" "Wii Play" "Wii Play (USA) (Rev 1).rvz")
    (mkGame "wiiSportsResort" "wii-sports-resort" "Wii Sports + Wii Sports Resort"
      "Wii Sports + Wii Sports Resort (USA) (En,Fr,Es).rvz"
    )
  ];
}
