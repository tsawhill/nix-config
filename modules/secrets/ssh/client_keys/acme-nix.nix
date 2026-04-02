{ config, lib, ... }:

let
  # A handy shorthand so we don't have to type the full path out every time
  cfg = config.my.secrets.sshclientkey.acme-nix;
in
{

  options.my.secrets.sshclientkey.acme-nix = {
    # lib.mkEnableOption automatically creates a boolean option that defaults to false.
    # The string provided is the description used if you ever generate man pages for your config.
    enable = lib.mkEnableOption "SSH client key for acme-nix";
  };

  # lib.mkIf ensures this entire block is ONLY evaluated if cfg.enable is set to true in a host's config.
  config = lib.mkIf cfg.enable {
    sops.secrets."id_ed25519" = {
      sopsFile = ./acme-nix.yaml;
      path = "/root/.ssh/id_ed25519";
      owner = "root";
      group = "root";
      mode = "0600"; # CRITICAL: SSH will ignore the key if this is anything else
    };
    sops.secrets."id_ed25519_pub" = {
      sopsFile = ./acme-nix.yaml;
      path = "/root/.ssh/id_ed25519.pub";
      owner = "root";
      group = "root";
      mode = "0644"; # CRITICAL: SSH will ignore the key if this is anything else
    };
  };
}
