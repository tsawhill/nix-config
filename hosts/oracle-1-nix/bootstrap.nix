{
  self,
  inputs,
  ...
}:

/*
  Phase-1 install target for nixos-anywhere.

  Deliberately contains no sops, no WireGuard and no nginx. The host's age key
  is derived from an SSH host key that does not exist until *after* the first
  install, so a config with sops secrets in it cannot activate on a fresh box —
  sops-nix fails the activation and nixos-anywhere reports the install as
  failed.

  So: install this, harvest /etc/ssh/ssh_host_ed25519_key.pub, enrol the age key
  in .sops.yaml, then `deploy oracle-1-nix` to switch to hosts/oracle-1-nix
  (the full config).
*/
let
  bootstrapSSHUsers = [ "root" ];
in
{
  networking.hostName = "oracle-1-nix";
  system.stateVersion = "26.05";

  imports = [
    inputs.disko.nixosModules.disko

    ./system/hardware.nix
    ./system/boot.nix
    ./system/networking-base.nix

    "${self}/modules/locale/enUS-pacific.nix"
    "${self}/modules/users"

    "${self}/modules/nix/nixpkgs.nix"
    "${self}/modules/nix/features.nix"

    "${self}/modules/ssh/openssh.nix"
    (import "${self}/modules/ssh/pubkeys/build-nix-root.nix" bootstrapSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-desktop-nix-taylor.nix" bootstrapSSHUsers)
    (import "${self}/modules/ssh/pubkeys/taylor-laptop-nix-taylor.nix" bootstrapSSHUsers)
  ];

  my.users.root.enable = true;

  # Public SSH is open *only* during bootstrap, because wg-remote does not
  # exist yet. The full config drops it back to the tunnel.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
