{
  lib,
  stdenvNoCC,
  coreutils,
  fetchurl,
  unzip,
  buildFHSEnv,
  appimageTools,
  channel ? "stable",
}:

let
  # Builds from YARG's own CI; a Unity build needs a licensed editor, so no
  # source build. BleedingEdge keeps every nightly, so old pins don't 404.
  releases = {
    stable = {
      version = "0.15.0";
      url = "https://github.com/YARC-Official/YARG/releases/download/v0.15.0/YARG_v0.15.0-Linux-x86_64.zip";
      sha256 = "a13bf5372096a920b6de98c7be299c864df6673b85d4c552f13fb2ea611917ca";
    };
    nightly = {
      version = "b4123";
      url = "https://github.com/YARC-Official/YARG-BleedingEdge/releases/download/b4123/YARG_b4123-Linux-x64.zip";
      sha256 = "97c3df8836f9c5942169f47d6225b2415b729132da9e1a58efe734a4c8be0d75";
    };
  };
  release = releases.${channel} or (throw "Unsupported YARG channel: ${channel}");

  game = stdenvNoCC.mkDerivation {
    pname = "yarg-${channel}-unwrapped";
    inherit (release) version;

    src = fetchurl { inherit (release) url sha256; };

    nativeBuildInputs = [ unzip ];

    unpackPhase = ''
      runHook preUnpack
      unzip -q "$src" -d game
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/yarg"
      cp -a game/. "$out/share/yarg/"
      # Mountpoint for the genre maps YARG downloads at runtime.
      mkdir -p "$out/share/yarg/YARG_Data/StreamingAssets/genres"
      runHook postInstall
    '';

    # Unity binaries resolve plugins via $ORIGIN; leave them untouched.
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
  };

  streamingAssets = "${game}/share/yarg/YARG_Data/StreamingAssets";
in
buildFHSEnv (
  appimageTools.defaultFhsEnvArgs
  // {
    pname = "yarg-${channel}";
    inherit (release) version;

    # Same env the launcher AppImage gave YARG, plus hidapi for HID instruments.
    targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ [ pkgs.hidapi ];

    # YARG updates song-source icons and genre maps inside its own install dir,
    # so give each channel writable copies of those two folders.
    extraPreBwrapCmds = ''
      state="''${XDG_DATA_HOME:-$HOME/.local/share}/yarg/${channel}"
      ${coreutils}/bin/mkdir -p "$state/sources" "$state/genres"
      if [ -z "$(${coreutils}/bin/ls -A "$state/sources")" ]; then
        ${coreutils}/bin/cp -r --no-preserve=mode ${streamingAssets}/sources/. "$state/sources/"
      fi
    '';
    extraBwrapArgs = [
      ''--bind "$state/sources" ${streamingAssets}/sources''
      ''--bind "$state/genres" ${streamingAssets}/genres''
    ];

    runScript = "${game}/share/yarg/YARG";

    meta = {
      description = "YARG (Yet Another Rhythm Game), ${channel} channel";
      homepage = "https://yarg.in";
      # Bundles the proprietary BASS audio library.
      license = with lib.licenses; [
        lgpl3Only
        unfreeRedistributable
      ];
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
)
