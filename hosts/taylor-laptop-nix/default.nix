{
  self,
  modulesPath,
  inputs,
  ...
}:

let
  desktopSSHUsers = [ "taylor" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "taylor-laptop-nix";
  system.stateVersion = "25.11";
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    # Boot
    ./system/boot.nix

    # Disks and alerts
    ./system/disks.nix
    # ./system/smart-alerts.nix
    # ./system/zfs-alerts.nix
    # ./system/zfs-scrub-trim.nix

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"
    # Network
    ./system/networking.nix

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/desktop.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Software
    "${self}/modules/software/bundles"

    # Desktop
    "${self}/modules/software/desktop"

    # Hardware
    "${self}/modules/software/services/openrgb.nix"

    # Remote build-server deploy trigger
    "${self}/modules/software/services/remote-deploy.nix"
  # Required when using home-manager as a NixOS module with useUserPackages = true
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  desktop.hyprland.enable = true;
  services.upower.enable = true;

  software.dev.enable = true;
  software.fonts.enable = true;
  software.apps.config.enable = true;
  software.apps.web.enable = true;
  software.apps.communication.enable = true;
  software.apps.media.enable = true;
  software.apps.gaming.enable = true;
  software.apps.emulators.enable = true;
  software.apps.printing.enable = true;
  software.apps.tools.enable = true;

  my.secrets.sshclientkey.laptop-nix.enable = true;
  my.users.taylor = {
    enable = true;
    extraGroups = [
      "i2c"
      "input"
      "video"
    ];
    sudoer = true;
  };
}
