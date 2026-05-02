{ lib, ... }:

let
  mkRoot = size: {
    root = {
      type = "disk";
      path = "/";
      pool = "rpool";
      inherit size;
    };
  };

  mkNixStore = name: {
    nix-store = {
      type = "disk";
      path = "/nix";
      source = "/mnt/nix-stores/${name}";
    };
  };

  mkEth0 = mac: {
    eth0 = {
      type = "nic";
      nictype = "bridged";
      parent = "br0";
      hwaddr = mac;
    };
  };

  mkLxc =
    name:
    {
      mac ? null,
      profiles ? [ "nixos-lxc" ],
      rootSize ? "4GiB",
      config ? { },
      devices ? { },
    }:
    {
      type = "container";
      inherit profiles config;
      devices =
        (mkRoot rootSize)
        // (mkNixStore name)
        // lib.optionalAttrs (mac != null) (mkEth0 mac)
        // devices;
    };
in
{
  my.incusDeclarative.instances = {
    OPNSense = {
      type = "virtual-machine";
      profiles = [ "default" ];
      config = {
        "boot.autostart" = "true";
        "boot.autostart.delay" = "5";
        "boot.autostart.priority" = "100";
        "limits.cpu" = "4";
        "limits.memory" = "8GiB";
        "raw.qemu" = "-cpu host";
      };
      devices = {
        root = {
          type = "disk";
          path = "/";
          pool = "rpool";
          size = "16GiB";
        };
        lan0 = {
          type = "nic";
          nictype = "bridged";
          parent = "br0";
          hwaddr = "14:29:0d:71:37:00";
        };
        wan0 = {
          type = "nic";
          nictype = "bridged";
          parent = "br1";
          hwaddr = "14:29:0d:71:37:01";
        };
      };
    };

    acme-nix = mkLxc "acme-nix" { mac = "bc:24:11:d5:6e:ab"; };
    adguard-nix = mkLxc "adguard-nix" { mac = "bc:24:11:cd:cd:ec"; };
    arrs-nix = mkLxc "arrs-nix" {
      mac = "BC:24:11:59:07:12";
      profiles = [
        "nixos-lxc"
        "media-mount"
        "downloadHDD-mount"
        "downloadSSD-mount"
      ];
    };
    authentik-nix = mkLxc "authentik-nix" { mac = "8e:95:4f:6e:c7:13"; };
    build-nix = mkLxc "build-nix" {
      mac = "bc:24:11:e1:63:a2";
      profiles = [
        "nixos-lxc"
        "nix-config-mount"
      ];
      config = {
        "limits.cpu" = "12";
        "limits.memory" = "24GiB";
      };
    };
    deluge-nix = mkLxc "deluge-nix" {
      mac = "bc:24:11:43:7d:c4";
      config."limits.memory" = "8GiB";
    };
    gotify-nix = mkLxc "gotify-nix" { mac = "bc:24:11:2b:3d:4a"; };
    immich-nix = mkLxc "immich-nix" { mac = "bc:24:11:de:09:b6"; };
    jellyfin-nix = mkLxc "jellyfin-nix" {
      mac = "bc:24:11:92:d7:50";
      config."limits.memory" = "16GiB";
    };
    jellyseerr-nix = mkLxc "jellyseerr-nix" { mac = "bc:24:11:23:f8:93"; };
    llm-nix = mkLxc "llm-nix" {
      mac = "bc:24:11:40:c1:43";
      rootSize = "32GiB";
    };
    local-nginx-nix = mkLxc "local-nginx-nix" { mac = "BC:24:11:42:40:51"; };
    nextcloud-nix = mkLxc "nextcloud-nix" { mac = "bc:24:11:60:3d:cc"; };
    pufferpanel-nix = mkLxc "pufferpanel-nix" {
      mac = "bc:24:11:9d:2b:70";
      config."limits.memory" = "8GiB";
    };
    romm-nix = mkLxc "romm-nix" {
      profiles = [
        "nixos-lxc"
        "roms-mount"
      ];
    };
    samba-nix = mkLxc "samba-nix" {
      mac = "bc:24:11:0f:b8:97";
      profiles = [
        "nixos-lxc"
        "nix-config-mount"
        "media-mount"
      ];
    };
    searx-nix = mkLxc "searx-nix" { mac = "02:FF:B9:66:68:1E"; };
    socks5-nix = mkLxc "socks5-nix" { mac = "bc:24:11:51:dd:4e"; };
    sunshine-nix = mkLxc "sunshine-nix" { mac = "10:66:6a:90:af:9f"; };
    syncthing-nix = mkLxc "syncthing-nix" {
      mac = "10:66:6a:aa:e3:ba";
      profiles = [
        "nixos-lxc"
        "roms-mount"
        "gamesaves-mount"
      ];
    };
    unbound-vpn-na-nix = mkLxc "unbound-vpn-na-nix" { mac = "a6:1e:69:87:fb:f3"; };
    vaultwarden-nix = mkLxc "vaultwarden-nix" { mac = "bc:24:11:f5:ac:e2"; };
  };
}
