{
  lib,
  callPackage,
  rpcs3,
}:

{
  name,
  desktopName,
  gamePath,
  args ? [ ],
  gamescopeArgs ? null,
  gamescopeResolutions ? [ ],
  env ? [ ],
  lsfgVkEnable ? false,
}:
let
  mkGameLauncher = callPackage ./mk-game-launcher.nix { };
  rpcs3Package = rpcs3.overrideAttrs (prev: {
    cmakeFlags = prev.cmakeFlags ++ [ (lib.cmakeBool "BUILD_SHARED_LIBS" false) ];
  });
  runner = callPackage ./runners/emulators/rpcs3.nix { rpcs3 = rpcs3Package; } {
    inherit gamePath args;
  };
in
mkGameLauncher {
  inherit
    name
    desktopName
    gamescopeArgs
    gamescopeResolutions
    env
    lsfgVkEnable
    ;
  inherit (runner) runnerCommand;
  setupScript = runner.setupScript or "";
}
