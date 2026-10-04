{
  imports = [
    ./known-hosts.nix
    ./authorized-keys.nix
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };
}
