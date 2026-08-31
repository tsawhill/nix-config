{
  self,
  modulesPath,
  inputs,
  ...
}:

let
  desktopSSHUsers = [ "root" ];
  laptopSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "root" ];
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
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" buildSSHUsers)
    (import "${self}/modules/ssh/pubkeys/phone-taylor.nix" phoneSSHUsers)

    # Users
    "${self}/modules/users"

    # Groups
    "${self}/modules/groups"

    # Home Manager
    ./home-manager.nix

    # Software
    "${self}/modules/software/bundles/server.nix"
  ];

  my.users.root = {
    enable = true;
  };
  my.garbage.collection.generations = 1;
  nix.settings = {
    keep-outputs = false;
    keep-derivations = false;
  };
  software.server.enable = true;
  my.monitoring.metrics.exporters.enable = true;
  # /proc/diskstats is host-global inside these containers, so node_exporter
  # would publish identical and misleading disk I/O for every guest. Incus's
  # host-side metrics endpoint provides the attributable counters instead.
  services.prometheus.exporters.node.disabledCollectors = [ "diskstats" ];
  environment.sessionVariables = {
    EDITOR = "nvim";
  };

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
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
  system.stateVersion = "26.05";
}
