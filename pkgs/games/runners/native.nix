{ lib }:

{
  command,
  args ? [ ],
  workingDirectory ? null,
}:
{
  setupScript = lib.optionalString (workingDirectory != null) ''
    cd ${lib.escapeShellArg workingDirectory}
  '';
  runnerCommand = lib.escapeShellArgs ([ command ] ++ args);
}
