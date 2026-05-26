{
  self,
  lib,
  modulesPath,
  inputs,
  pkgs,
  ...
}:

let
  desktopSSHUsers = [ "taylor" ];
  laptopSSHUsers = [ "taylor" ];
  serverSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "taylor" ];
in
{
  networking.hostName = "pi-backup-nix";
  system.stateVersion = "25.11";
  imports = [
    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Home Manager
    ./home-manager.nix
    ./system/disks.nix
    ./system/networking.nix
    ./system/cloudflare-ddns.nix
    ./system/zfs-backup-target.nix
    # Locale
    "${self}/modules/locale/enUS-pacific.nix"

    # NixOS Settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # Users
    "${self}/modules/users"
    # Groups
    "${self}/modules/groups"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/server-nix-root.nix" serverSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Software
    # "${self}/modules/software/bundles/all.nix"
    "${self}/modules/software/packages/zsh.nix"
    # "${self}/modules/software/services/incus.nix"

    # Nginx
    "${self}/modules/software/services/nginx/nginx.nix"
    "${self}/modules/software/services/nginx/proxies"
    "${self}/modules/software/services/nginx/streams/minecraft.nix"

    # fail2ban
    "${self}/modules/software/services/fail2ban"

  ];
  # NixOS defaults include x86-only modules (e.g. i8042) that don't exist
  # in the Pi's ARM kernel, causing the initrd build to fail.
  boot.initrd.includeDefaultModules = false;

  # Use the new nixos-raspberrypi kernel bootloader; disable extlinux
  # which gets pulled in by the aarch64 sd-image module.
  # Manual headless recovery: this bootloader keeps previous generations under
  # /boot/firmware/nixos/. If a bad deploy wedges the Pi, edit the FAT boot
  # partition from another machine and change config.txt's os_prefix from
  # nixos/default/ to a retained generation such as nixos/123-default/.
  boot.loader.raspberry-pi.bootloader = "kernel";
  boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

  # Bypass the Pi 5 boot-time PSU safety check. The Pi warns and halts
  # at a red screen if it detects a <5A USB-PD supply, even when the
  # board is actually powered via GPIO (e.g. from a SATA HAT). This
  # makes headless/remote reboots work without pressing the power button.
  hardware.raspberry-pi.config.all.options.usb_max_current_enable = {
    enable = true;
    value = 1;
  };

  # Enable the external PCIe x1 slot (off by default on Pi 5). Required
  # for the Radxa Penta SATA HAT (JMB585) to appear in lspci.
  # The JMB585 SATA controller can only do 32-bit DMA but the Pi 5 IOMMU
  # assigns IOVA addresses above 4 GiB by default, causing AHCI probe to
  # fail with ENOMEM. This overlay constrains the PCIe IOVA range to 32-bit.
  hardware.raspberry-pi.config.all.dt-overlays = {
    pcie-32bit-dma-pi5 = {
      enable = true;
    };
  };

  hardware.raspberry-pi.config.all.base-dt-params = {
    pciex1 = {
      enable = true;
    };
    # Gen3 is unofficial but the JMB585 handles it reliably and doubles
    # throughput vs the default Gen2.
    pciex1_gen = {
      enable = true;
      value = 3;
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    25565
  ];
  networking.firewall.allowedUDPPorts = [ 27017 ];

  my.nginx.geoblock.enable = true;

  my.secrets.wireguard.pi-backup-nix.enable = true;

  users.users.nginx = {
    # This tells NixOS not to use the 'nologin' shell
    shell = pkgs.zsh;
  };

  my.users.taylor = {
    enable = true;
    sudoer = true;
  };
  my.groups = {
    media = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1000;
    };
    download = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1001;
    };
    gameservers = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1002;
    };
    code = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1003;
    };
    documents = {
      enable = true;
      members = [
        "root"
        "taylor"
      ];
      gid = 1004;
    };
  };

  proxy.authentik = {
    enable = true;
    domain = "auth.tsawhill.org";
  };

  proxy.vaultwarden = {
    enable = true;
    domain = "vault.tsawhill.org";
  };
  proxy.immich = {
    enable = true;
    domain = "immich.tsawhill.org";
  };
  proxy.jellyfin = {
    enable = true;
    domain = "jelly.tsawhill.org";
  };
  proxy.nextcloud = {
    enable = true;
    domain = "nc.tsawhill.org";
  };
  proxy.open-webui = {
    enable = true;
    domain = "llm.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.gotify = {
    enable = true;
    domain = "gotify.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.radarr = {
    enable = true;
    domain = "rad.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.sonarr = {
    enable = true;
    domain = "son.tsawhill.org";
    # mTLSCert = "mTLS-CA";
    enableAuthentik = true;
  };
  proxy.lidarr = {
    enable = true;
    domain = "lid.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.prowlarr = {
    enable = true;
    domain = "pro.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.seerr = {
    enable = true;
    domain = "request.tsawhill.org";
  };
  proxy.unifi = {
    enable = true;
    domain = "unifi.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
  proxy.searx = {
    enable = true;
    domain = "searx.tsawhill.org";
    mTLSCert = "mTLS-CA";
  };
}
