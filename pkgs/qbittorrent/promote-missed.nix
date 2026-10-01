{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "qbit-promote-missed";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./qbit_promote.py
      ./qbit_promote_missed.py
      ./test_qbit_promote.py
      ./test_qbit_promote_missed.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  # Standard library only; the tests use fakes and contact no hosts.
  doCheck = true;
  nativeCheckInputs = [ python3 ];
  checkPhase = ''
    runHook preCheck
    python3 -B -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # Installed side by side so `import qbit_promote` resolves.
  installPhase = ''
    runHook preInstall
    install -Dm444 -t $out/libexec/qbit-promote-missed qbit_promote.py qbit_promote_missed.py
    makeWrapper ${python3.interpreter} $out/bin/qbit-promote-missed \
      --add-flags "-B $out/libexec/qbit-promote-missed/qbit_promote_missed.py"
    runHook postInstall
  '';

  meta.mainProgram = "qbit-promote-missed";
}
