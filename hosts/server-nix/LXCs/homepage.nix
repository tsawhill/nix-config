{ self, ... }:
{
  imports = [
    ./base
  ];

  my.monitoring.homepage.enable = true;
  networking.hostName = "homepage-nix";
}
