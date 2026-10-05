{ pkgs, lib }:
let
  revision = "5517e0cf0d1acd16a1618eeedec596957523f9e1";
  archive = pkgs.fetchurl {
    url = "https://github.com/Anjok07/ultimatevocalremovergui/archive/${revision}.tar.gz";
    sha256 = "d1ec1de6328f9b4dc26fe5b1616b4cad068e4e6b29d7ade6b505294db9b24d57";
  };
  source = pkgs.runCommand "uvr-source-${revision}" { } ''
    mkdir -p "$out"
    tar -xzf ${archive} -C "$out" --strip-components=1
    # CPU only; installing both ONNX runtimes overwrites the same Python module.
    sed -i '/^onnxruntime-gpu/d' "$out/requirements.txt"
    # PyPI's Dora is an unrelated data-analysis package with a broken sklearn
    # dependency. This revision has no active dora imports (Demucs comments it out).
    sed -i '/^Dora==/d' "$out/requirements.txt"
    # librosa 0.9 imports pkg_resources, removed in newer setuptools.
    echo 'setuptools==80.9.0' >> "$out/requirements.txt"
  '';
  python = pkgs.python311.withPackages (p: [ p.tkinter ]);
  launcher = pkgs.writeShellScript "uvr-launch" ''
    export UVR_SOURCE=${source}
    export UVR_ENV_VERSION=${revision}-cpu-1
    export UVR_CONSTRAINTS=${./constraints.txt}
    exec bash ${./launch.sh} "$@"
  '';
in
pkgs.buildFHSEnv {
  name = "ultimate-vocal-remover";
  targetPkgs = p: [
    python
    p.uv
    p.ffmpeg
    p.rubberband
    p.libsndfile
    p.libsamplerate
    p.gcc
    p.gnumake
    p.pkg-config
    p.stdenv.cc.cc.lib
    p.zlib
    p.glib
    p.libGL
    p.libGLU
    p.freetype
    p.fontconfig
    p.libx11
    p.libxext
    p.libxrender
    p.libxft
    p.libxinerama
    p.libxcursor
    p.libxrandr
    p.libxi
    p.xclip
    p.bash
    p.coreutils
    p.util-linux
    p.cacert
  ];
  runScript = launcher;
  meta = {
    description = "Ultimate Vocal Remover with a writable CPU-only Python environment";
    homepage = "https://github.com/Anjok07/ultimatevocalremovergui";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ultimate-vocal-remover";
  };
}
