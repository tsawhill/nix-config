{ pkgs, ... }:
let
  # Nushell skips interactiveShellInit, so it gets the same translation as a wrapper.
  nuSops = pkgs.writeTextDir "share/nushell/vendor/autoload/sops.nu" ''
    def --wrapped sops [...rest] {
      let key = if (is-admin) { ^ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key | complete } else { { exit_code: 1 } }
      if $key.exit_code == 0 {
        with-env { SOPS_AGE_KEY: ($key.stdout | str trim) } { ^sops ...$rest }
      } else {
        ^sops ...$rest
      }
    }
  '';
in
{
  environment.systemPackages = with pkgs; [
    sops
    ssh-to-age
    nuSops
  ];
  environment.pathsToLink = [ "/share/nushell" ];
  environment.interactiveShellInit = ''
    # Invisibly translate the SSH host key for the SOPS CLI
    if [ "$USER" = "root" ]; then
      alias sops="SOPS_AGE_KEY=\$(ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key 2>/dev/null) sops"
    fi
  '';
}
