# Base image the NixOS factory provisions every new LXC from.
#
# Two artifacts are built from this configuration and must always come from
# the same build:
#   - system.build.tarball   -> the Incus rootfs image (barebones-nixos-allow-keys)
#   - the nix/store inside it -> the ZFS template snapshot cloned into /nix
#
# It is deliberately bare. Its only job is to boot, get a DHCP lease, and
# accept an SSH connection from build-nix so colmena can push the real
# configuration. Keep it on the same nixpkgs the LXC nodes deploy from
# (nixpkgs-stable) — version skew between this base and the deployed closure
# is what breaks switch-to-configuration on first deploy.
{
  self,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" [ "root" ])
  ];

  # Nothing is ever installed from a channel here; colmena pushes closures.
  system.installer.channel.enable = false;
  installer.cloneConfig = false;

  # lxc-instance-common re-enables these at priority 890; override it.
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;

  # startWhenNeeded would work, but colmena connects within seconds of boot
  # and a listening sshd is one less thing to race.
  services.openssh = {
    enable = true;
    startWhenNeeded = false;
    settings.PasswordAuthentication = false;
  };

  # Mirrors the networking in ./default.nix so the template behaves the same
  # way before and after the first deploy.
  networking = {
    dhcpcd.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
    firewall.enable = false;
  };

  services.resolved.enable = true;

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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.tmp.useTmpfs = true;

  system.stateVersion = "26.05";
}
