{ config, lib, ... }:

let
  credentialsPath = "/run/secrets/smb-samba-nix-credentials";
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,mfsymlinks";
in
{
  my.secrets.umbriel-pass.enable = true;
  sops.secrets.umbriel-pass.neededForUsers = lib.mkForce false;

  sops.templates."smb-samba-nix-credentials" = {
    content = ''
      username=umbriel
      domain=taylor-home
      password=${config.sops.placeholder."umbriel-pass"}
    '';
    path = credentialsPath;
    mode = "0400";
  };

  fileSystems."/mnt/zpool/code/nix-config" = {
    device = "//10.73.73.4/nix-configs/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/media" = {
    device = "//10.73.73.4/media/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/gameSSD" = {
    device = "//10.73.73.4/gameSSD/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
