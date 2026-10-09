{
  config,
  lib,
  self,
  modulesPath,
  inputs,
  networkTopology,
  ...
}:

let
  lan = networkTopology.networks.lan;
  inherit (networkTopology.lib) lanIp;
  lanPrefix = lib.last (lib.splitString "/" lan.cidr);
in
{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"

    # Secrets (SOPS)
    inputs.sops-nix-stable.nixosModules.sops
    "${self}/modules/secrets"

    # Locale
    "${self}/modules/locale/enUS-pacific.nix"

    # Nix settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/cachix.nix"
    "${self}/modules/nix/garbage-collection.nix"
    "${self}/modules/monitoring"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"

    # Users
    "${self}/modules/users"

    # Groups
    "${self}/modules/groups"

    # Software
    "${self}/modules/software/bundles/headless.nix"
  ];

  my.users.root = {
    enable = true;
  };
  my.garbage.collection.generations = 1;
  # The downloadHDD/nix-stores datasets already dedup across containers.
  my.garbage.collection.optimise = lib.mkDefault false;
  nix.settings = {
    keep-outputs = false;
    keep-derivations = false;
  };
  # No own kernel, so booted-system only pins old generations from GC.
  system.activationScripts.lxcBootedSystem = ''
    ln -sfn "$(readlink -f "$systemConfig")" /run/booted-system
  '';
  software.headless.enable = true;

  # lxc-container.nix pulls in the installer channel: a 197 MiB nixpkgs copy
  # and a cleanSource walk of all of nixpkgs on every eval.
  system.installer.channel.enable = false;
  installer.cloneConfig = false;
  # Old containers still carry a root channel profile; this warns until it's removed.
  nix.channel.enable = false;

  my.monitoring.metrics.exporters.enable = true;
  my.monitoring.logs.agent.enable = true;
  # /proc/diskstats is host-global inside these containers, so node_exporter
  # would publish identical and misleading disk I/O for every guest. Incus's
  # host-side metrics endpoint provides the attributable counters instead.
  services.prometheus.exporters.node.disabledCollectors = [ "diskstats" ];

  # This enables the tmpfs (RAM) mount for /tmp
  boot.tmp.useTmpfs = true;

  networking = {
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
  };

  systemd.network = {
    enable = true;
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      # Static from topology so no LXC waits on networking-dhcp-nix at boot.
      networkConfig = {
        Address = "${lanIp config.networking.hostName}/${lanPrefix}";
        Gateway = lib.mkDefault lan.gateway;
        DNS = [ (lanIp lan.dnsHost) ];
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
  system.stateVersion = "26.05";
}
