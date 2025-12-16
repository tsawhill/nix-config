{
  pkgs,
  inputs,
  ...
}:
{
  users.users.taylor = {
    uid = 1000;
    isNormalUser = true;
    home = "/home/taylor";

    # Set zsh as default shell
    # Package installed with home-manager, so skip check
    ignoreShellProgramCheck = true;
    shell = pkgs.zsh;

    description = "taylor";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh = {
      authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMBFsmNzZWYPyqHORl40pfN7RXrHlXFjN8EEmAhhlSIE taylor@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHlvVCxPlxJUJ5xZKNbry8XKxUZBA1RRbE3dgwxRDf7o taylor@pixel9pro"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAhCihzQsgE8Q6eM18c2BnUIaDgek0Mh9n1X9DPaLI4c taylor@taylor-nixlaptop"
      ];
    };
  };

  # Mount samba share for NixOS configuration
  fileSystems."/home/taylor/.config/nixos" = {
    device = "//10.73.73.4/nix-configs/nixos";
    fsType = "cifs";
    options =
      let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

      in
      [ "${automount_opts},credentials=/home/taylor/.smbsecrets,uid=1000,mfsymlinks" ];
  };

  imports = [
    ./home-manager
  ];
}
