{
  lib,
  stdenv,
  fetchFromGitLab,
  pkg-config,
  wayland,
  wayland-protocols,
  wayland-scanner,
  wlr-protocols,
  cairo,
  pango,
  libxkbcommon,
  fontconfig,
  systemdLibs,
}:

stdenv.mkDerivation rec {
  pname = "hyprcrosshair";
  version = "0-unstable-2025-10-11";

  src = fetchFromGitLab {
    owner = "tsawhill";
    repo = "hyprcrosshair";
    rev = "refs/heads/feature/new-features";
    hash = "sha256-Iq8uq9wOAAajPRaONrgzsUHQRKw+WDA2DJBcfyTT9zY=";
  };

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    wayland-protocols
    wlr-protocols
    cairo
    pango
    libxkbcommon
    fontconfig
    systemdLibs
  ];

  # Fix hardcoded protocol paths and remove -march=native
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail '/usr/share/wayland-protocols' '${wayland-protocols}/share/wayland-protocols' \
      --replace-fail '/usr/share/wlr-protocols' '${wlr-protocols}/share/wlr-protocols' \
      --replace-fail '-march=native ' "" \
      --replace-fail '/usr/local' "$out" \
      --replace-fail '$(DESTDIR)/usr/share' "$out/share"
    grep -rl '/usr/local/bin/' . | xargs -r sed -i "s|/usr/local/bin/|$out/bin/|g"
  '';

  makeFlags = [
    "DESTDIR="
  ];

  installFlags = [
    "DESTDIR="
  ];

  # Install target creates dirs and copies files to /usr/local — our substituteInPlace
  # already rewrites /usr/local to $out, so just run make install
  preInstall = ''
    mkdir -p $out/bin
    mkdir -p $out/share/hyprcrosshair/img
    mkdir -p $out/share/hyprcrosshair/fonts
    mkdir -p $out/share/applications
  '';

  meta = {
    description = "Crosshair overlay for Hyprland with GUI settings and system tray support";
    homepage = "https://gitlab.com/whitleystriber/hyprcrosshair";
    license = lib.licenses.lgpl3Plus;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "hyprcrosshair";
  };
}
