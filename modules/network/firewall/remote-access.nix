# WireGuard remote-access policy, enforced on networking-vpn-in-nix.
# Names are topology hosts with a wgRemote.ip; every such host must be listed here once.
{
  # Anything: the LAN, other peers, and the internet if the client routes it through the tunnel.
  trusted = [
    "taylor-desktop-nix"
    "taylor-laptop-nix"
    "taylor-deck-nix"
    "taylor-cube-nix"
    "taylor-phone"
  ];

  # AdGuard DNS plus the upstreams their own nginx proxies and streams point at,
  # read from each host's NixOS config so the allowlist follows the proxy list.
  restricted = [
    "pi-backup-nix"
    "remote-nginx-nix"
  ];
}
