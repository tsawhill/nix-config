{ lib, pkgs, ... }:
{
  services.pufferpanel = {
    enable = true;
    extraPackages = with pkgs; [
      bash
      curl
      gawk
      gnutar
      gzip
      javaPackages.compiler.openjdk21
    ];
    package = pkgs.buildFHSEnv {
      name = "pufferpanel-fhs";
      runScript = lib.getExe pkgs.pufferpanel;
      targetPkgs =
        pkgs': with pkgs'; [
          icu
          openssl
          zlib
        ];
    };
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
