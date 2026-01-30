{ self, modulesPath, ... }:

let
  desktopSSHUsers = [ "root" ];
  laptopSSHUsers = [ "root" ];
  buildSSHUsers = [ "root" ];
  phoneSSHUsers = [ "root" ];
in
{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"

    # Nix settings
    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"
    "${self}/modules/nix/keep-outputs-derivations.nix"
    "${self}/modules/nix/garbage-collection.nix"

    # SSH Access
    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/keys/desktop.nix" desktopSSHUsers)
    (import "${self}/modules/ssh/keys/laptop.nix" laptopSSHUsers)
    (import "${self}/modules/ssh/keys/build.nix" buildSSHUsers)
    (import "${self}/modules/ssh/keys/phone.nix" phoneSSHUsers)

    # Users
    "${self}/modules/users"

    # Groups
    "${self}/modules/groups"

    # Home Manager
    ./home-manager.nix

    # Software
    "${self}/modules/software/bundles/all.nix"
  ];

  my.users.root = {
    enable = true;
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
