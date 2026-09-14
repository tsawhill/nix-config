{ config, lib, ... }:
let
  # Guitar layouts come from modules/software/guitars profiles; without it the
  # DLL falls back to the MiniHost layout it used to hardcode.
  shimConfig = config.software.apps.gaming.guitarShimConfig or "";
in
{
  software.games.entries.guitarHero3 = {
    command = "gh3";
    desktopName = "Guitar Hero III";
    category = "Guitar Hero";
    env = [
      "WINEDLLOVERRIDES=xinput1_3=n,b"
      "vblank_mode=0"
    ]
    ++ lib.optional (shimConfig != "") "GUITAR_SHIM_CONFIG=${shimConfig}";
    basePath = "pc/GH3";
    runner.umu = {
      exe = "GH3.exe";
      # GH3 is 32-bit: its GPU drivers and fonts only resolve inside umu's Steam
      # Runtime container. That used to rule out proton-cachyos, whose only build
      # was host-native and missing libunwind in the container -- but upstream now
      # ships a -slr build made for the runtime, so the default applies here.
    };
  };
}
