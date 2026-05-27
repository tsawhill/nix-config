{ self, config, inputs, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/rebuild-scripts.nix"
    "${self}/modules/monitoring"

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
  my.secrets.sshclientkey.build-nix-root.enable = true;
  my.secrets.github_access_token_public.enable = true;
  my.secrets.smtp_password_server.enable = true;
  my.secrets.gotify_token_deploy.enable = true;
  my.monitoring = {
    deployAlerts.enable = true;
    notifications = {
      recipientEmail = "me@tsawhill.org";
      smtp = {
        host = "smtp.purelymail.com";
        port = 587;
        user = "server@tsawhill.org";
        from = "server@tsawhill.org";
        passwordFile = config.sops.secrets.smtp_password_server.path;
      };
      gotify = {
        url = "https://gotify.tsawhill.org/message";
        tokenFile = config.sops.secrets.gotify_token_deploy.path;
      };
    };
  };
  my.groups = {
    code = {
      enable = true;
      members = [ "root" ];
      gid = 1003;
    };
  };
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings = {
    substituters = [
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://kopuz.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "kopuz.cachix.org-1:J2X3AnAYhKTJW5S3aCLoA1ckonQXVNZMQvhZA0YAufw="
    ];
  };
  environment.systemPackages =
    let
      pkgs-master = import inputs.nixpkgs-master {
        system = "x86_64-linux";
      };
    in
    [ pkgs-master.claude-code ];
  my.garbage.collection.prunePerHostProfiles = true;
  networking.hostName = "build-nix";
}
