{
  lib,
  appimageTools,
  fetchurl,
  runCommand,
  unzip,
}:
let
  pname = "jellium-desktop";
  commit = "41bcfd7c9a1e26a2b6f418e814e6e44f9227cb6d";
  shortCommit = builtins.substring 0 7 commit;
  version = "0.1.0-dev+${shortCommit}";
  appimageName = "JelliumDesktop-${version}-x86_64.AppImage";

  # Upstream has no releases or tags yet. Pin the successful GitHub Actions
  # build by both run ID and content hash instead of following its moving
  # `main` nightly URL.
  artifact = fetchurl {
    url = "https://nightly.link/andrewrabert/jellium-desktop/actions/runs/31070003843/linux-appimage-x86_64.zip";
    hash = "sha256-DlRw6V36cPPhVD0iRuQTBPo0b+xP9QgCPQXyOxFfmgw=";
  };

  src = runCommand appimageName { nativeBuildInputs = [ unzip ]; } ''
    unzip -p ${artifact} ${appimageName} > "$out"
    chmod +x "$out"
  '';

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 \
      ${appimageContents}/usr/share/applications/net.nullsum.JelliumDesktop.desktop \
      "$out/share/applications/net.nullsum.JelliumDesktop.desktop"
    install -Dm444 \
      ${appimageContents}/usr/share/icons/hicolor/scalable/apps/net.nullsum.JelliumDesktop.svg \
      "$out/share/icons/hicolor/scalable/apps/net.nullsum.JelliumDesktop.svg"
  '';

  meta = {
    description = "Unofficial Jellyfin desktop client built on CEF and mpv";
    homepage = "https://github.com/andrewrabert/jellium-desktop";
    license = lib.licenses.gpl2Only;
    mainProgram = "jellium-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
