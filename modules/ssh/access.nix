# Interactive SSH logins: which key may log in to which host, as which users.
# ./authorized-keys.nix turns this into each host's authorized keys and the list
# of user@host pairs the nushell ssh completer offers. Forced-command keys
# (mtls-ca, syncoid, VPN triggers) stay with their services.
{
  # Named <host>-<user> after the login that holds the private key.
  keys = {
    build-nix-root = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMpZvx4kihRZV1pBxeHwsaIug7sgv7LSZrFl+P+of0fK root@build-nix";
    phone-taylor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHlvVCxPlxJUJ5xZKNbry8XKxUZBA1RRbE3dgwxRDf7o";
    server-nix-root = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIgDZS+J0kNLLpc5DFdMTh4c4sdS/9lmocOvR3ZCaojP root@server-nix";
    taylor-cube-nix-taylor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPycGOOnN9uu8oQxxWB54HDrRSN8+MfRs1C5Og7Srrp taylor@taylor-cube-nix";
    taylor-desktop-nix-taylor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMBFsmNzZWYPyqHORl40pfN7RXrHlXFjN8EEmAhhlSIE taylor@nixos";
    taylor-laptop-nix-taylor = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAhCihzQsgE8Q6eM18c2BnUIaDgek0Mh9n1X9DPaLI4c taylor@taylor-nixlaptop";
  };

  # key -> target host -> users. `incus-guests` means every LXC on server-nix.
  grants = {
    # Colmena deploys everything from here.
    build-nix-root = {
      incus-guests = [ "root" ];
      pi-backup-nix = [ "root" ];
      remote-nginx-nix = [ "root" ];
      server-nix = [ "root" ];
      taylor-cube-nix = [ "root" ];
      taylor-deck-nix = [ "root" ];
      taylor-desktop-nix = [ "root" ];
      taylor-laptop-nix = [ "root" ];
    };

    phone-taylor = {
      incus-guests = [ "root" ];
      pi-backup-nix = [ "taylor" ];
      remote-nginx-nix = [ "root" ];
      server-nix = [ "taylor" ];
      taylor-cube-nix = [ "taylor" ];
      taylor-deck-nix = [ "taylor" ];
      taylor-desktop-nix = [ "taylor" ];
      taylor-laptop-nix = [ "taylor" ];
    };

    server-nix-root.pi-backup-nix = [ "root" ];

    taylor-cube-nix-taylor = {
      # `deploy` runs over ssh on build-nix.
      build-nix = [ "root" ];
      # USB/IP sharing from the cube into sunshine-nix.
      server-nix = [ "taylor" ];
      # USB/IP sharing from the cube.
      taylor-desktop-nix = [ "taylor" ];
    };

    taylor-desktop-nix-taylor = {
      incus-guests = [ "root" ];
      pi-backup-nix = [ "taylor" ];
      remote-nginx-nix = [ "root" ];
      server-nix = [ "taylor" ];
      taylor-cube-nix = [ "taylor" ];
      taylor-deck-nix = [ "taylor" ];
      taylor-laptop-nix = [ "taylor" ];
    };

    taylor-laptop-nix-taylor = {
      incus-guests = [ "root" ];
      pi-backup-nix = [ "taylor" ];
      remote-nginx-nix = [ "root" ];
      server-nix = [ "taylor" ];
      taylor-cube-nix = [ "taylor" ];
      taylor-deck-nix = [ "taylor" ];
      taylor-desktop-nix = [ "taylor" ];
    };
  };
}
