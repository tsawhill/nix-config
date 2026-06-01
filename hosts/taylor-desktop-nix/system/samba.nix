{ config, lib, ... }:
{
  my.secrets.immobile0783-pass.enable = true;
  sops.secrets.immobile0783-pass.neededForUsers = lib.mkForce false;

  sops.templates."smb-nix-config-credentials" = {
    content = ''
      username=immobile0783
      domain=taylor-home
      password=${config.sops.placeholder."immobile0783-pass"}
    '';
    path = "/run/secrets/smb-nix-config-credentials";
    mode = "0400";
  };

  fileSystems."/mnt/nix-config" = {
    device = "//10.73.73.4/nix-configs/";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
      in
      [ "${automount_opts},credentials=/run/secrets/smb-nix-config-credentials,uid=1000,mfsymlinks" ];
  };

  fileSystems."/mnt/gameSSD" = {
    device = "//10.73.73.4/gameSSD/";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
      in
      [ "${automount_opts},credentials=/run/secrets/smb-nix-config-credentials,uid=1000,mfsymlinks" ];
  };
}
