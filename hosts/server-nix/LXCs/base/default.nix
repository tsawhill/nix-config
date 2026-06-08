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
    "${self}/modules/nix/keep-outputs-derivations.nix"
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
    "${self}/modules/software/bundles"
  ];

  my.users.root = {
    enable = true;
  };
  my.garbage.collection.generations = 2;
  my.monitoring.metrics.exporters.enable = true;
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
  system.stateVersion = "25.11";
}
