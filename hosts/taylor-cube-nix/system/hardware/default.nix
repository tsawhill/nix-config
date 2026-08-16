{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./cpu.nix
    # cec.nix and leds.nix are superseded by jovian.devices.steammachine.
    # The CEC one MUST stay out: it re-registered amdgpu's notifier at boot,
    # which would mask whether the profile actually fixes the race.
  ];
}
