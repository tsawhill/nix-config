{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./cpu.nix
    ./cec.nix
    ./leds.nix
  ];
}
