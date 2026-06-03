{
  lib,
  dolphin-emu,
}:

{
  gamePath,
  args ? [ ],
}:
{
  runnerCommand = lib.escapeShellArgs (
    [
      (lib.getExe dolphin-emu)
      "--batch"
      "--exec"
      gamePath
    ]
    ++ args
  );
}
