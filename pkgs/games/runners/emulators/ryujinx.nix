{
  lib,
  ryubing,
}:

{
  gamePath,
  args ? [ ],
}:
{
  runnerCommand = lib.escapeShellArgs (
    [
      (lib.getExe ryubing)
      gamePath
    ]
    ++ args
  );
}
