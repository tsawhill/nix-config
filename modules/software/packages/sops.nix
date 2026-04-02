{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    sops
    ssh-to-age
  ];
  environment.interactiveShellInit = ''
    # Invisibly translate the SSH host key for the SOPS CLI
    if [ "$USER" = "root" ]; then
      alias sops="SOPS_AGE_KEY=\$(ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key 2>/dev/null) sops"
    fi
  '';
}
