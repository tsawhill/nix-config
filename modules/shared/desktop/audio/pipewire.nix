{
  pkgs,
  ...
}:
{
  # Enable pipewire and pipewire-pulse.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # Include pulseaudio package for cli audio control
  environment.systemPackages = with pkgs; [
    pulseaudio
  ];
}
