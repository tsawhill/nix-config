let
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "PS2";
      basePath = "ps2/${file}";
      runner.emulator.type = "pcsx2";
    };
  };
in
{
  software.games.entries = builtins.listToAttrs [
    (mkGame "godOfWarPs2" "god-of-war-ps2" "God of War (PS2)" "God of War.iso")
    (mkGame "godOfWarIIPs2" "god-of-war-ii-ps2" "God of War II (PS2)" "God of War II .iso")
    (mkGame "mortalKombatShaolinMonksPs2" "mortal-kombat-shaolin-monks-ps2"
      "Mortal Kombat: Shaolin Monks (PS2)"
      "Mortal Kombat - Shaolin Monks (USA).iso"
    )
  ];
}
