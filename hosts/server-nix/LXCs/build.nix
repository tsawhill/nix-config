{
  self,
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cubeSSHUsers = [ "root" ];

  # TEMP: nixos-26.05 ships claude-code 2.1.223 and the VSCodium remote server's
  # bundled extension CLI is 2.1.278; neither knows claude-opus-5-5. Take the CLI
  # from unstable and point the extension at it. Drop unstablePkgs, claudeWrapper,
  # the claude-code overlay, and the Machine settings file once the extension
  # ships a CLI that has the model.
  unstablePkgs = import inputs.nixpkgs-unstable {
    localSystem = config.nixpkgs.hostPlatform.system;
    config.allowUnfree = true;
  };

  # The extension execs the wrapper as `wrapper <its own claude> <args>`.
  claudeWrapper = pkgs.writeShellScript "claude-code-wrapper" ''
    if [ "$#" -gt 0 ]; then shift; fi
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';
in
{
  imports = [
    ./base

    # SSH Access: taylor@taylor-cube-nix, on top of base's key set
    (import "${self}/modules/ssh/pubkeys/taylor-cube-nix-taylor.nix" cubeSSHUsers)
    "${self}/modules/software/bundles/dev.nix"
    "${self}/modules/software/services/rebuild-scripts.nix"
    "${self}/modules/software/packages/nixos-factory.nix"
    "${self}/modules/software/packages/qbit-promote-tui.nix"

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
    # The deploy controller explicitly pins the system closures needed for
    # retries and rollback. Do not also retain every build-time output reachable
    # through those roots; that turned the builder into a permanent build cache.
    keep-outputs = lib.mkForce false;
    keep-derivations = lib.mkForce false;
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
  # Allow VS Code Remote SSH server to run
  programs.nix-ld.enable = true;
  software.dev.enable = true;

  nixpkgs.overlays = [ (_final: _prev: { claude-code = unstablePkgs.claude-code; }) ];

  home-manager.users.root.home.file.".vscodium-server/data/Machine/settings.json".text =
    builtins.toJSON
      { "claudeCode.claudeProcessWrapper" = "${claudeWrapper}"; };

  networking.hostName = "build-nix";
}
