# Incus desired state for server-nix. Every topology guest managed by server-nix
# gets an instance; eth0 and the /nix store come from topology, and `guests`
# below only lists what differs from that default.
{ lib, networkTopology }:

let
  incusGuests = lib.filterAttrs (
    _: host: (host.incus.manager or null) == "server-nix"
  ) networkTopology.hosts;

  # Device names follow the host path, e.g. /mnt/zpool/media -> mnt_zpool_media.
  mountProfile = description: paths: {
    inherit description;
    devices = lib.listToAttrs (
      map (path: {
        name = lib.removePrefix "_" (lib.replaceStrings [ "/" ] [ "_" ] path);
        value = {
          type = "disk";
          inherit path;
          source = path;
          shift = "true";
        };
      }) paths
    );
  };

  dirMount = path: mountProfile "Disk passthrough for ${baseNameOf path} directory" [ path ];

  lxcSecurity = {
    "security.idmap.base" = "100000";
    "security.idmap.isolated" = "true";
    "security.idmap.size" = "65535";
    "security.nesting" = "true";
  };

  rootDisk = pool: size: {
    type = "disk";
    path = "/";
    inherit pool size;
  };

  # Each guest lives wholly on one tier: an Incus pool named after the tier on
  # <zpool>/lxc/incus, holding both its root disk (containers/<guest>) and its
  # /nix as the custom volume store-<guest> (custom/default_store-<guest>).
  # Incus mounts both only while the guest runs. critical is mirrored NVMe for
  # what the network can't run without; standard is single-disk scratchSSD.
  # zfs-backups.nix copies every root disk hourly to zpool/backups/<same path>.
  tiers = {
    critical.zpool = "rpool";
    standard.zpool = "scratchSSD";
  };
  defaultTier = "standard";
  defaultRootSize = "4GiB";

  storeVolume = guest: "store-${guest}";

  # Incus pools the apply service creates if missing (never modifies existing ones).
  storagePools = lib.mapAttrs (_: tier: {
    driver = "zfs";
    config = {
      source = "${tier.zpool}/lxc/incus";
      "volume.zfs.use_refquota" = "true";
    };
  }) tiers;

  profiles = {
    default.description = "Default Incus profile";

    nixos-lxc = {
      description = "Base NixOS LXC config";
      config = lxcSecurity // {
        "boot.autostart" = "true";
        "limits.cpu" = "2";
        "limits.memory" = "2GiB";
      };
      devices = {
        eth0 = {
          type = "nic";
          nictype = "bridged";
          parent = "br0";
        };
        # TODO: switch to "standard" once the old rpool pool is retired.
        root = rootDisk "rpool" defaultRootSize;
      };
    };

    nixos-router-lxc = {
      description = "NixOS router LXC config without inherited LAN eth0";
      config = lxcSecurity // {
        "boot.autostart" = "false";
        "limits.cpu" = "2";
        "limits.memory" = "2GiB";
      };
      devices.root = rootDisk "rpool" defaultRootSize;
    };

    nvidia-gpu = {
      description = "Physical NVIDIA GPU and host userspace runtime passthrough";
      # Explicitly override any stale live setting from the nvidia.runtime pilot.
      config."nvidia.runtime" = "false";
      devices = {
        gpu-1 = {
          type = "gpu";
          gputype = "physical";
          pci = "0000:0b:00.0";
          gid = "26";
          mode = "0660";
        };
        nvidia-runtime = {
          type = "disk";
          source = "/run/host-nvidia-runtime";
          path = "/opt/host-nvidia-runtime";
          readonly = "true";
        };
      };
    };

    downloadHDD-mount = dirMount "/mnt/downloadHDD";
    downloadSSD-mount = dirMount "/mnt/downloadSSD";
    ffsync-mount = dirMount "/mnt/zpool/ffsync";
    gamesaves-mount = dirMount "/mnt/zpool/gamesaves";
    gameserver-mount = mountProfile "Disk passthrough for gameserver directory" [
      "/mnt/zpool/gameservers"
    ];
    immich-mount = dirMount "/mnt/zpool/immich";
    media-mount = dirMount "/mnt/zpool/media";
    nextcloud-mount = dirMount "/mnt/zpool/nextcloud";
    nix-config-mount = mountProfile "Disk passthrough for nixos config directory" [
      "/mnt/zpool/code/nix-config"
    ];
    roms-mount = dirMount "/mnt/zpool/roms";
    taylor-mount = mountProfile "Disk passthrough for Taylor's datasets" [
      "/mnt/zpool/taylor/clips"
      "/mnt/zpool/taylor/documents"
      "/mnt/zpool/taylor/work"
    ];
  };

  # Per-guest differences: extra profiles (after nixos-lxc), config, devices,
  # rootSize (default defaultRootSize), and tier (a tiers key, default defaultTier).
  guests = {
    adguard-nix = {
      config."boot.autostart.priority" = "70";
      tier = "critical";
    };
    arrs-nix = {
      profiles = [
        "media-mount"
        "downloadHDD-mount"
        "downloadSSD-mount"
      ];
      config."limits.memory" = "8GiB";
      rootSize = "8GiB";
    };
    # vaultwarden signs in through it.
    authentik-nix.tier = "critical";
    build-nix = {
      profiles = [ "nix-config-mount" ];
      config = {
        "limits.cpu" = "12";
        "limits.memory" = "24GiB";
      };
    };
    ca-nix.rootSize = "4GiB";
    ffsync-nix = {
      profiles = [ "ffsync-mount" ];
      rootSize = "4GiB";
    };
    homeassistant-nix = {
      config = {
        "limits.cpu" = "2";
        "limits.memory" = "4GiB";
      };
      rootSize = "16GiB";
    };
    immich-nix.profiles = [
      "immich-mount"
      "nvidia-gpu"
    ];
    jellyfin-nix = {
      profiles = [
        "media-mount"
        "nvidia-gpu"
      ];
      config."limits.memory" = "16GiB";
      rootSize = "32GiB";
    };
    llm-nix = {
      profiles = [ "nvidia-gpu" ];
      rootSize = "32GiB";
    };
    # vaultwarden is only reachable through it.
    local-nginx-nix.tier = "critical";
    monitoring-nix = {
      config = {
        "limits.cpu" = "2";
        "limits.memory" = "4GiB";
      };
      rootSize = "32GiB";
    };
    networking-ddns-nix = {
      rootSize = "4GiB";
      tier = "critical";
    };
    networking-dhcp-nix = {
      config."boot.autostart.priority" = "90";
      rootSize = "4GiB";
      tier = "critical";
    };
    # eth0 is the legacy LAN; each zone gets its own NIC on its VLAN, named after the zone.
    # wan stays down until takeover, when the router gives it OPNsense's WAN MAC (Incus refuses duplicates).
    networking-router-nix = {
      config."boot.autostart.priority" = "100";
      rootSize = "4GiB";
      tier = "critical";
      devices =
        lib.mapAttrs (zone: _: {
          type = "nic";
          nictype = "bridged";
          parent = "br0";
          vlan = toString networkTopology.zones.${zone}.vlan;
          hwaddr = "02:c9:07:cb:e2:${toString networkTopology.zones.${zone}.vlan}";
          name = zone;
        }) networkTopology.zones
        // {
          wan = {
            type = "nic";
            nictype = "bridged";
            parent = "br1";
            hwaddr = "02:c9:07:cb:e2:99";
            name = "wan";
          };
          transit = {
            type = "nic";
            nictype = "bridged";
            parent = networkTopology.networks.vpnInTransit.bridge;
            hwaddr = "02:2b:99:b7:74:01";
            name = "transit";
          };
        };
    };
    networking-vpn-in-nix = {
      config."boot.autostart.priority" = "90";
      rootSize = "4GiB";
      tier = "critical";
    };
    networking-vpn-out-eu1-nix = {
      config."boot.autostart.priority" = "90";
      rootSize = "4GiB";
      tier = "critical";
    };
    networking-vpn-out-na1-nix = {
      config."boot.autostart.priority" = "90";
      rootSize = "4GiB";
      tier = "critical";
    };
    nextcloud-nix.profiles = [
      "nextcloud-mount"
      "downloadHDD-mount"
    ];
    palworld-nix = {
      config = {
        "limits.cpu" = "4";
        "limits.memory" = "16GiB";
      };
      rootSize = "50GiB";
    };
    pufferpanel-nix.config."limits.memory" = "8GiB";
    pyload-nix = {
      profiles = [
        "downloadHDD-mount"
        "downloadSSD-mount"
      ];
      rootSize = "8GiB";
    };
    qbit-gen-nix = {
      profiles = [
        "downloadHDD-mount"
        "downloadSSD-mount"
      ];
      config."limits.memory" = "4GiB";
      rootSize = "8GiB";
    };
    qbit-lts-nix = {
      profiles = [
        "downloadHDD-mount"
        "downloadSSD-mount"
      ];
      config."limits.memory" = "6GiB";
      rootSize = "8GiB";
    };
    qui-nix = {
      config."limits.memory" = "2GiB";
      rootSize = "4GiB";
    };
    samba-nix.profiles = [
      "nix-config-mount"
      "media-mount"
      "downloadHDD-mount"
      "downloadSSD-mount"
      "roms-mount"
      "taylor-mount"
    ];
    sunshine-nix = {
      profiles = [
        "nvidia-gpu"
        "downloadHDD-mount"
        "roms-mount"
      ];
      config = {
        "limits.cpu" = "4";
        "limits.memory" = "8GiB";
      };
      rootSize = "8GiB";
      devices = {
        uinput = {
          type = "unix-char";
          source = "/dev/uinput";
          path = "/dev/uinput";
          mode = "0660";
          gid = "174";
        };
        sunshine-input = {
          type = "unix-hotplug";
          vendorid = "beef";
          productid = "dead";
          required = "false";
          mode = "0660";
          gid = "174";
        };
        host-udev-data = {
          type = "disk";
          source = "/run/udev/data";
          path = "/opt/host-udev-data";
          readonly = "true";
        };
        gamesaves = {
          type = "disk";
          source = "/mnt/zpool/gamesaves";
          path = "/mnt/gamesaves";
          shift = "true";
        };
      };
    };
    syncthing-nix = {
      profiles = [
        "gamesaves-mount"
        "roms-mount"
        "nix-config-mount"
      ];
      rootSize = "4GiB";
    };
    unbound-vpn-na-nix = {
      config."boot.autostart.priority" = "80";
      tier = "critical";
    };
    unifi-nix.rootSize = "4GiB";
    vaultwarden-nix.tier = "critical";
  };

  mkInstance =
    name: host:
    let
      extra = guests.${name} or { };
      tierName = extra.tier or defaultTier;
    in
    {
      type = "container";
      profiles = [ "nixos-lxc" ] ++ extra.profiles or [ ];
      config =
        lib.optionalAttrs (host.incus.intermittent or false) { "boot.autostart" = "false"; }
        // extra.config or { };
      devices = lib.recursiveUpdate (
        {
          root = rootDisk tierName (extra.rootSize or defaultRootSize);
          nix-store = {
            type = "disk";
            path = "/nix";
            pool = tierName;
            source = storeVolume name;
          };
          eth0 = {
            type = "nic";
            nictype = "bridged";
            parent =
              if (host.attachment or "lan") == "transit" then
                networkTopology.networks.vpnInTransit.bridge
              else
                "br0";
            hwaddr = host.lan.mac;
          };
        }
      ) (extra.devices or { });
    };

  unknownGuests = lib.attrNames (builtins.removeAttrs guests (lib.attrNames networkTopology.hosts));
in
assert lib.assertMsg (
  unknownGuests == [ ]
) "incus registry: not in topology: ${toString unknownGuests}";
{
  inherit
    profiles
    storagePools
    tiers
    defaultTier
    ;
  instances = lib.mapAttrs mkInstance incusGuests;
}
