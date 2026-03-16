{
  config,
  self,
  pkgs,
  ...
}:

{
  imports = [
    ./base
    ../hardware/nvidia.nix # Import NVIDIA driver configuration for encoding support
    "${self}/modules/software/services/sunshine.nix"
  ];

  programs.xwayland.enable = true;
  networking.hostName = "sunshine-nix";
  services.desktopManager.plasma6.enable = true;

  # Enable graphics drivers to utilize your passed-through GPU
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.systemPackages = with pkgs; [
    sunshine
    kdePackages.kscreen
    xwayland
    kdePackages.qtwayland
    xorg.xcbutilcursor
  ];

  # Required for Sunshine to inject controller/mouse/keyboard inputs
  boot.kernelModules = [ "uinput" ];

  users.users.taylor = {
    isNormalUser = true;
    # 'render' and 'video' are crucial for accessing the passed-through GPU DRM nodes
    extraGroups = [
      "wheel"
      "video"
      "input"
      "render"
    ];
  };

  # Declaratively define the headless session user service
  systemd.user.services.plasma-headless = {
    description = "Headless KDE Plasma Wayland Session";
    wantedBy = [ "default.target" ];

    path = with pkgs; [
      kdePackages.kwin
      kdePackages.plasma-workspace
      xwayland
      # We can safely drop the manual qt/xcb plugins we added earlier
      # because the NixOS profile will handle them now.
    ];

    serviceConfig = {
      Type = "simple";
      # The -l flag tells bash to source /etc/profile, pulling in all Qt variables
      # exec replaces the bash process with kwin to keep systemd process tracking clean
      ExecStart = "${pkgs.bash}/bin/bash -l -c 'exec kwin_wayland --virtual --xwayland startplasma-wayland'";
      Restart = "on-failure";
      RestartSec = "5";
    };

    environment = {
      KWIN_WAYLAND_VIRTUAL_SCREENS = "1";
    };
  };
}
