{ pkgs, ... }:
{
  imports = [ ./sunshine.nix ];
  environment.systemPackages = with pkgs; [ eddie ];
  nixpkgs.config.permittedInsecurePackages = [
    "dotnet-sdk-6.0.428"
    "dotnet-runtime-6.0.36"
  ];
}
