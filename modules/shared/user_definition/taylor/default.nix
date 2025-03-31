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
    shell = pkgs.fish;
    description = "taylor";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh = {
      authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHKxZDZJ/yaWX/A9ZhXU8F3CmcJ+jPYkatshJoEqJPZy tdog@arch"
      ];
    };
  };
  fileSystems."/home/taylor/.config/nixos" = {
    device = "//192.168.2.4/nixos-configs/nixos";
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
