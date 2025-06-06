{
  pkgs,
  ...
}:
{
  # Enable appimages
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # OBS With plugins
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = [
      pkgs.obs-studio-plugins.obs-pipewire-audio-capture
      pkgs.obs-studio-plugins.wlrobs
      pkgs.obs-studio-plugins.obs-vkcapture
    ];
  };

  environment.systemPackages = with pkgs; [
    # Terminal emulator
    foot

    # File Management
    nemo-with-extensions
    filezilla

    # Browsers
    floorp
    ungoogled-chromium

    # Communication
    vesktop

    # Multimedia
    feishin
    mpv
  ];
}
