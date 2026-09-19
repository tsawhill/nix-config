{ self, ... }:
let
  # qui cannot start without its session secret, so both wait for SOPS.
  secretsProvisioned = false;
in
{
  imports = [
    ./base
    "${self}/modules/software/services/qui.nix"
  ];

  networking.hostName = "qui-nix";

  my.secrets.qui_session_secret.enable = secretsProvisioned;

  # No data mounts and no VPN client: qui only speaks HTTP to the qBittorrent
  # web UIs on the LAN.
  my.services.qui.enable = secretsProvisioned;
}
