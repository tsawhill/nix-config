{
  config,
  lib,
  networkTopology,
  ...
}:

let
  credentialsPath = "/run/secrets/smb-cube-credentials";
  sambaHost = networkTopology.lib.fqdn "samba-nix";
  # Lazy automount: only mounts on first access and never blocks boot. Games this
  # host selects (software.games.syncGames) are on local disk and launch without
  # ever touching this share; unselected games launch from here over the LAN.
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,mfsymlinks";
in
{
  my.secrets.cube8801-pass.enable = true;
  sops.secrets.cube8801-pass.neededForUsers = lib.mkForce false;

  sops.templates."smb-cube-credentials" = {
    content = ''
      username=cube8801
      domain=taylor-home
      password=${config.sops.placeholder."cube8801-pass"}
    '';
    path = credentialsPath;
    mode = "0400";
  };

  fileSystems."/mnt/zpool/roms" = {
    device = "//${sambaHost}/roms/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
