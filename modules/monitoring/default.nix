{
  # Reusable host monitoring bundle.
  #
  # Hosts opt in with a single `my.monitoring = { ... };` block. The shared
  # notification module owns SMTP/Gotify settings, while the feature modules
  # below decide which services to enable.
  imports = [
    ./metrics.nix
    ./notifications.nix
    ./smart-alerts.nix
    ./zfs-alerts.nix
    ./zfs-maintenance.nix
  ];
}
