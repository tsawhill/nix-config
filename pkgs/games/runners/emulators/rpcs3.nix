{
  lib,
  rpcs3,
}:

{
  gamePath,
  args ? [ ],
}:
{
  runnerCommand = lib.escapeShellArgs (
    [
      (lib.getExe rpcs3)
      "--no-gui"
      gamePath
    ]
    ++ args
  );
}
