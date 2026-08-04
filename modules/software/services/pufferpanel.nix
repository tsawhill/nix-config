{
  inputs,
  pkgs,
  ...
}:

let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
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
    package = unstablePkgs.pufferpanel;
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
