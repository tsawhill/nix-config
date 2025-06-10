{
  imports = [
    ./audio
    ./gnome
  ];

  services.libinput.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
}
