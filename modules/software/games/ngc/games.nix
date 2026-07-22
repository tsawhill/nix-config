let
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "GameCube";
      basePath = "ngc/${file}";
      runner.emulator.type = "dolphin";
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "luigisMansionNgc" "luigis-mansion-ngc" "Luigi's Mansion (GameCube)"
      "Luigi's Mansion (USA).rvz"
    )
    (mkGame "marioGolfToadstoolTourNgc" "mario-golf-toadstool-tour-ngc"
      "Mario Golf: Toadstool Tour (GameCube)"
      "Mario Golf - Toadstool Tour (USA).rvz"
    )
    (mkGame "marioKartDoubleDashNgc" "mario-kart-double-dash-ngc" "Mario Kart: Double Dash!! (GameCube)"
      "Mario Kart - Double Dash!! (USA).rvz"
    )
    (mkGame "marioParty4Ngc" "mario-party-4-ngc" "Mario Party 4 (GameCube)" "Mario Party 4 (USA).rvz")
    (mkGame "marioParty5Ngc" "mario-party-5-ngc" "Mario Party 5 (GameCube)" "Mario Party 5 (USA).rvz")
    (mkGame "marioParty6Ngc" "mario-party-6-ngc" "Mario Party 6 (GameCube)" "Mario Party 6 (USA).rvz")
    (mkGame "marioParty7Ngc" "mario-party-7-ngc" "Mario Party 7 (GameCube)"
      "Mario Party 7 (USA) (Rev 1).rvz"
    )
    (mkGame "mortalKombatDeadlyAllianceNgc" "mortal-kombat-deadly-alliance-ngc"
      "Mortal Kombat: Deadly Alliance (GameCube)"
      "Mortal Kombat - Deadly Alliance (USA).rvz"
    )
    (mkGame "mortalKombatDeceptionNgc" "mortal-kombat-deception-ngc"
      "Mortal Kombat: Deception (GameCube)"
      "Mortal Kombat - Deception (USA).rvz"
    )
    (mkGame "spongebobBattleForBikiniBottomNgc" "spongebob-battle-for-bikini-bottom-ngc"
      "SpongeBob SquarePants: Battle for Bikini Bottom (GameCube)"
      "Nickelodeon SpongeBob SquarePants - Battle for Bikini Bottom (USA).rvz"
    )
    (mkGame "pikminNgc" "pikmin-ngc" "Pikmin (GameCube)" "Pikmin (USA).rvz")
    (mkGame "pikmin2Ngc" "pikmin-2-ngc" "Pikmin 2 (GameCube)" "Pikmin 2 (USA).rvz")
    (mkGame "spiderMan2Ngc" "spider-man-2-ngc" "Spider-Man 2 (GameCube)" "Spider-Man 2 (USA).rvz")
    (mkGame "superMarioSunshineNgc" "super-mario-sunshine-ngc" "Super Mario Sunshine (GameCube)"
      "Super Mario Sunshine (USA).rvz"
    )
    (mkGame "superSmashBrosMeleeNgc" "super-smash-bros-melee-ngc" "Super Smash Bros. Melee (GameCube)"
      "Super Smash Bros. Melee (USA) (En,Ja) (Rev 2).rvz"
    )
    (mkGame "warioWareMegaPartyGameNgc" "warioware-mega-party-game-ngc"
      "WarioWare, Inc.: Mega Party Game$! (GameCube)"
      "WarioWare, Inc. - Mega Party Game$! (USA).rvz"
    )
  ];
}
