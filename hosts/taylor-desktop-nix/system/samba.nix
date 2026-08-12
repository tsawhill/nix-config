{
  config,
  lib,
  networkTopology,
  ...
}:

let
  credentialsPath = "/run/secrets/smb-nix-config-credentials";
  sambaHost = networkTopology.lib.fqdn "samba-nix";
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,mfsymlinks";
  readOnlyMountOptions = "${mountOptions},ro";
in
{
  my.secrets.immobile0783-pass.enable = true;
  sops.secrets.immobile0783-pass.neededForUsers = lib.mkForce false;

  sops.templates."smb-nix-config-credentials" = {
    content = ''
      username=immobile0783
      domain=taylor-home
      password=${config.sops.placeholder."immobile0783-pass"}
    '';
    path = credentialsPath;
    mode = "0400";
  };

  fileSystems."/mnt/nix-config" = {
    device = "//${sambaHost}/nix-configs/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/downloadHDD" = {
    device = "//${sambaHost}/downloadHDD/";
    fsType = "cifs";
    options = [ readOnlyMountOptions ];
  };

  fileSystems."/mnt/downloadSSD" = {
    device = "//${sambaHost}/downloadSSD/";
    fsType = "cifs";
    options = [ readOnlyMountOptions ];
  };

  fileSystems."/mnt/gameSSD" = {
    device = "//${sambaHost}/gameSSD/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/taylor/clips" = {
    device = "//${sambaHost}/clips/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/taylor/documents" = {
    device = "//${sambaHost}/documents/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/taylor/work" = {
    device = "//${sambaHost}/work/";
    fsType = "cifs";
    options = [ mountOptions ];
  };

  fileSystems."/mnt/zpool/roms" = {
    device = "//${sambaHost}/roms/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
