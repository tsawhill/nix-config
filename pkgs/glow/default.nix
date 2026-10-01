{
  lib,
  buildGoModule,
  rsync,
}:
buildGoModule {
  pname = "glow";
  version = "2.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./main.go
      ./main_test.go
    ];
  };

  # Standard library only.
  vendorHash = null;
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
  ];

  # The tests drive a real local rsync.
  nativeCheckInputs = [ rsync ];

  meta.mainProgram = "glow";
}
