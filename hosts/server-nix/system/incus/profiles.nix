{
  my.incusDeclarative.profiles = {
    default = {
      description = "Default Incus profile";
    };

    nixos-lxc = {
      description = "Base NixOS LXC config";
      config = {
        "boot.autostart" = "true";
        "limits.cpu" = "2";
        "limits.memory" = "2GiB";
        "security.idmap.base" = "100000";
        "security.idmap.isolated" = "true";
        "security.idmap.size" = "65535";
        "security.nesting" = "true";
      };
      devices = {
        eth0 = {
          type = "nic";
          nictype = "bridged";
          parent = "br0";
        };
        root = {
          type = "disk";
          path = "/";
          pool = "rpool";
          size = "4GiB";
        };
      };
    };

    media-mount = {
      description = "Disk passthrough for media directory";
      devices."/mnt/zpool/media" = {
        type = "disk";
        path = "/mnt/zpool/media";
        source = "/mnt/zpool/media";
        shift = "true";
      };
    };

    nix-config-mount = {
      description = "Disk passthrough for nixos config directory";
      devices."/mnt/zpool/code/nix-config" = {
        type = "disk";
        path = "/mnt/zpool/code/nix-config";
        source = "/mnt/zpool/code/nix-config";
        shift = "true";
      };
    };

    roms-mount = {
      description = "Disk passthrough for roms directory";
      devices."/mnt/zpool/roms" = {
        type = "disk";
        path = "/mnt/zpool/roms";
        source = "/mnt/zpool/roms";
        shift = "true";
      };
    };

    gamesaves-mount = {
      description = "Disk passthrough for gamesaves directory";
      devices.gamesaves = {
        type = "disk";
        path = "/mnt/zpool/gamesaves";
        source = "/mnt/zpool/gamesaves";
        shift = "true";
      };
    };

    gameserver-mount = {
      description = "Disk passthrough for gameserver directory";
      devices."/mnt/zpool/gameservers" = {
        type = "disk";
        path = "/mnt/zpool/gameservers";
        source = "/mnt/zpool/gameservers";
        shift = "true";
      };
    };

    downloadHDD-mount = {
      description = "Disk passthrough for downloadHDD directory";
      devices.downloadHDD = {
        type = "disk";
        path = "/mnt/downloadHDD";
        source = "/mnt/downloadHDD";
        shift = "true";
      };
    };

    downloadSSD-mount = {
      description = "Disk passthrough for downloadSSD directory";
      devices.downloadSSD = {
        type = "disk";
        path = "/mnt/downloadSSD";
        source = "/mnt/downloadSSD";
        shift = "true";
      };
    };
  };
}
