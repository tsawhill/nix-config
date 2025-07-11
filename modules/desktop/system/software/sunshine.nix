{ pkgs-master, ... }:
{
  services.sunshine = {
    package = pkgs-master.sunshine;
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
}
