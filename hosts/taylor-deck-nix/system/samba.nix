{
  config,
  lib,
  networkTopology,
  ...
}:

let
  credentialsPath = "/run/secrets/smb-deck-credentials";
  sambaHost = networkTopology.lib.fqdn "samba-nix";
  # Lazy automount: only mounts on first access and never blocks boot, so the
  # deck still boots fine off-LAN. Games kept locally (software.games.localGames)
  # launch without ever touching this share.
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,gid=100,forceuid,forcegid,file_mode=0664,dir_mode=0775,noperm,mfsymlinks";
in
{
  my.secrets.pelican8334-pass.enable = true;
  sops.secrets.pelican8334-pass.neededForUsers = lib.mkForce false;

  sops.templates."smb-deck-credentials" = {
    content = ''
      username=pelican8334
      domain=taylor-home
      password=${config.sops.placeholder."pelican8334-pass"}
    '';
    path = credentialsPath;
    mode = "0400";
  };

  fileSystems."/mnt/gameSSD" = {
    device = "//${sambaHost}/gameSSD/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
