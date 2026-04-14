{
  config,
  self,
  pkgs,
  ...
}:

{
  imports = [
    ./base
    ../hardware/nvidia.nix
    "${self}/modules/software/services/sunshine.nix"
  ];

  networking.hostName = "sunshine-nix";
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = false;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  environment.systemPackages = with pkgs; [
    kdePackages.kscreen
    kdePackages.qtwayland
    xorg.xcbutilcursor
  ];

  boot.kernelModules = [ "uinput" ];

  users.users.taylor = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "input"
      "render"
    ];
  };

  # Without linger, user services never start (no login = no session)
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/taylor 0644 root root -"
  ];

  systemd.user.services.plasma-headless = {
    description = "Headless KDE Plasma Wayland Session";
    wantedBy = [ "default.target" ];
    after = [ "dbus.socket" ];

    path = with pkgs; [
      kdePackages.kwin
      kdePackages.plasma-workspace
      xwayland
    ];

    serviceConfig = {
      Type = "simple";
      # startplasma-wayland starts kwin internally — calling kwin directly here
      # would spawn two compositors fighting each other
      ExecStart = "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
      Restart = "on-failure";
      RestartSec = "5";
    };

    environment = {
      KWIN_WAYLAND_VIRTUAL_SCREENS = "1";
      WAYLAND_DISPLAY = "wayland-1";
    };
  };

  # Sunshine connects to the plasma Wayland session
  systemd.user.services.sunshine = {
    after = [ "plasma-headless.service" ];
    wants = [ "plasma-headless.service" ];
    environment = {
      WAYLAND_DISPLAY = "wayland-1";
      DISPLAY = ":0";
    };
  };
}
