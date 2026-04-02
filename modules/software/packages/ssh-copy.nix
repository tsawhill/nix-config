{ pkgs, ... }:

{
  environment.systemPackages = [
    # Creates a custom command to pipe text through SSH to your local clipboard
    (pkgs.writeShellScriptBin "ssh-copy" ''
      # Reads stdin, base64 encodes it without line wrapping, and wraps it in OSC 52
      printf "\033]52;c;%s\a" "$(base64 -w0)"
    '')
  ];
}
