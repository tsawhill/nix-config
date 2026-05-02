{
  imports = [
    ./known-hosts.nix
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };
}
