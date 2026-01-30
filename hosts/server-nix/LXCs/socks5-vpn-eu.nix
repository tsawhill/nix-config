{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/3proxy.nix"
  ];
  networking.hostName = "socks5-vpn-eu-nix";

  environment.etc = {
    "3proxy.passwd".text = ''
      taylor:CR:$1$bO1YgxPW$wQFYJWIpD12d7CRnY4NHL1
    '';
  };
}
