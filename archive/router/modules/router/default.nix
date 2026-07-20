{
  # Public option schema and small typed data models.
  imports = [
    ./options.nix

    # Runtime backends generated from the schema above.
    ./networking.nix
    ./dhcp.nix
    ./wireguard.nix
    ./firewall.nix
  ];
}
