{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/adguard.nix"
  ];
  networking.hostName = "adguard-nix";

  /**
    Disable resolved DNS listener
    This occupies port 53 and does not allow adguard to use it
  */
  services.resolved.extraConfig = ''
    DNSStubListener=no
  '';
}
