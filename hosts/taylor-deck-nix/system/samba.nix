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
  # deck still boots fine off-LAN. Games this host selects
  # (software.games.syncGames) are on local disk and launch without touching this
  # share; unselected games launch from here over the LAN.
  automountOptions = "x-systemd.automount,noauto,nofail,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target,_netdev";
  mountOptions = "${automountOptions},credentials=${credentialsPath},uid=1000,mfsymlinks";
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

  fileSystems."/mnt/zpool/roms" = {
    device = "//${sambaHost}/roms/";
    fsType = "cifs";
    options = [ mountOptions ];
  };
}
