{
  imports = [
    ./systemd-boot.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "amd_pstate=active" ];
}
