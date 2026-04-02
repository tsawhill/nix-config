{ self, inputs, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/rebuild-scripts.nix"

    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"
    "${self}/modules/software/packages/sops.nix"
  ];
  environment.sessionVariables = {
    SOPS_AGE_SSH_PRIVATE_KEY_FILE = "/etc/ssh/ssh_host_ed25519_key";
  };
  nix.extraOptions = ''
    !include /run/secrets/github_access_token_public
  '';
  my.secrets.sshclientkey.build-nix.enable = true;
  my.secrets.github_access_token_public.enable = true;
  my.groups = {
    code = {
      enable = true;
      members = [ "root" ];
      gid = 1003;
    };
  };
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  networking.hostName = "build-nix";
}
