{
  imports = [
    ./hyprland
    ./audio
  ];

  services.libinput.enable = true;

  services.xserver = {
    enable = true;
    # Enable GDM with autologin as you need to enter decryption key on boot
    displayManager = {
      gdm = {
        enable = true;
      };
    };
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "taylor";
  };
  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
}
