{ self, ... }:
{
  imports = [
    ./base
  ];

  my.monitoring.homepage = {
    enable = true;
    weather.location = "Folsom, California, United States";
  };
  networking.hostName = "homepage-nix";
}
