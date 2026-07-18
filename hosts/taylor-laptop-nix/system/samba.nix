{
  config,
  lib,
  networkTopology,
  ...
}:

let
  credentialsPath = "/run/secrets/smb-samba-nix-credentials";
  sambaHost = networkTopology.lib.fqdn "samba-nix";
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,gid=100,forceuid,forcegid,file_mode=0664,dir_mode=0775,noperm,mfsymlinks";
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
    device = "//${sambaHost}/nix-configs/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/media" = {
    device = "//${sambaHost}/media/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/gameSSD" = {
    device = "//${sambaHost}/gameSSD/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
