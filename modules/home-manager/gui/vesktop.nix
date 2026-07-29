{
  programs.vesktop = {
    enable = true;

    # Vesktop remains installed by software.apps.vesktop so the desktop can
    # keep its hardware-acceleration wrapper. Home Manager owns settings only.
    package = null;

    settings = {
      discordBranch = "stable";
      splashColor = "rgb(221, 221, 221)";
      splashBackground = "rgb(18, 18, 20)";
      spellCheckLanguages = [
        "en-US"
        "en"
      ];
      disableSmoothScroll = false;
      minimizeToTray = true;
      tray = true;
      checkUpdates = false;
      appBadge = false;
      clickTrayToShowHide = false;
      splashTheming = false;
      customTitleBar = false;
      hardwareAcceleration = true;
      hardwareVideoAcceleration = true;
      enableSplashScreen = false;
      audio = {
        workaround = true;
        ignoreVirtual = true;
        deviceSelect = true;
        granularSelect = true;
        ignoreDevices = false;
        ignoreInputMedia = true;
        onlySpeakers = false;
      };
    };

    # Intentionally leave vencord.settings unmanaged: the current mutable file
    # contains a plugin API key and must never be copied into the Nix store.
  };
}
