{
  pkgs,
  pkgs-floorp,
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
    pkgs-floorp.floorp
    ungoogled-chromium

    # Communication
    vesktop

    lingot

    # Downloading
    deluge-gtk
    pyload-ng

    # Multimedia
    feishin
    mpv
    jellyfin-media-player

    #Editors
    kdePackages.kdenlive
    gimp

    # Printing and modeling
    # orca-slicer
    freecad

    #Misc
    monero-gui

    audacity
    gparted
  ];

  virtualisation.waydroid.enable = true;

}
