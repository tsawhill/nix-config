{
  software.games.entries.guitarHero3 = {
    command = "gh3";
    desktopName = "Guitar Hero III";
    category = "Guitar Hero";
    env = [
      "WINEDLLOVERRIDES=xinput1_3=n,b"
      "vblank_mode=0"
      "PULSE_LATENCY_MSEC=60"
    ];
    runner.umu = {
      exePath = "/mnt/gameSSD/Games/GH3/GH3.exe";
      # GH3 is 32-bit: its GPU drivers and fonts only resolve inside umu's sniper
      # container, which proton-cachyos (host-native, missing libunwind in sniper)
      # can't run in. GE-Proton is built for sniper, so use it here, pinned.
      proton = "ge-proton";
      protonVersion = "9-25";
    };
  };
}
