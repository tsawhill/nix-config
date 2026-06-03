{
  lib,
  pcsx2,
}:

{
  gamePath,
  args ? [ ],
}:
{
  runnerCommand = lib.escapeShellArgs (
    [
      (lib.getExe pcsx2)
      gamePath
    ]
    ++ args
  );
}
