{
  lib,
  retroarch,
}:

{
  gamePath,
  core,
  args ? [ ],
}:
{
  runnerCommand = lib.escapeShellArgs (
    [
      (lib.getExe retroarch)
      "-L"
      core
      gamePath
    ]
    ++ args
  );
}
