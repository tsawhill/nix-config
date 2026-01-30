{ lib, ... }:
{
  nixpkgs = {
    config = {
      allowUnfree = true;
    };
    hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
