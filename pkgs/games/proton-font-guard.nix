{ python3, writeShellScriptBin }:
writeShellScriptBin "proton-font-guard" ''
  exec ${python3}/bin/python3 ${./proton-font-guard.py} "$@"
''
