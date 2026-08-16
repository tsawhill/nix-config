let
  mkGame = id: command: desktopName: file: {
    name = id;
    value = {
      inherit command desktopName;
      category = "Switch";
      basePath = "switch/${file}";
      runner.emulator.type = "ryujinx";
    };
  };
in
{
  # Ryujinx needs prod.keys and firmware installed into ~/.config/Ryujinx before
  # any of these boot; neither ships here. Game updates live in each title's
  # patches/ dir and are applied from the emulator's own UI, not the CLI.
  software.games.entries = builtins.listToAttrs [
    (mkGame "paperMarioTtydSwitch" "paper-mario-ttyd-switch"
      "Paper Mario: The Thousand-Year Door (Switch)"
      "Paper Mario The Thousand-Year Door [0100ECD018EBE000][US][v0].nsp"
    )
    (mkGame "superMarioBrosWonderSwitch" "super-mario-bros-wonder-switch"
      "Super Mario Bros. Wonder (Switch)"
      "Super Mario Bros. Wonder/Super Mario Bros. Wonder[010015100B514000][v0].nsp"
    )
    (mkGame "superMarioOdysseySwitch" "super-mario-odyssey-switch" "Super Mario Odyssey (Switch)"
      "Super Mario Odyssey (World)/Super Mario Odyssey (World) (En,Ja,Fr,De,Es,It,Nl,Zh,Ru) (Rev 3).xci"
    )
  ];
}
