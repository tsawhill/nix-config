# Archived: NixOS `router` scaffolding

This was an unfinished attempt to run the home router (DHCP / firewall / WireGuard server) as a
NixOS LXC (`router-nix`). It was **never deployed** — the LXC does not exist, and **OPNsense does all
routing, DHCP, and WireGuard**. It was archived on 2026-07-20 because the dormant config made the
repo look like `router-nix` was the live WG/DHCP host.

The files here mirror their original repo paths for easy revival.

## What was moved
- `modules/router/` — the reusable router module (`my.router.*`: dhcp, firewall, networking, wireguard).
- `hosts/server-nix/LXCs/router.nix` — the LXC host config that instantiated it.
- `modules/secrets/wireguard/router-nix.{nix,yaml}` — router-only WireGuard sops secret.

## What was changed elsewhere when archiving (revert these to revive)
- `flake-outputs/server.nix` — removed the `router-nix = nixpkgs-stable.lib.nixosSystem { … };`
  `nixosConfigurations` entry.
- `flake.nix` — removed `router = import ./modules/router;` from `nixosModules`.
- `flake-outputs/colmena.nix` — removed the already-commented `router-nix` Colmena node line.
- `modules/network/topology.nix` — the old `router-nix` host entry was **renamed to `opnsense`**
  (it only ever provided the LAN gateway `10.73.73.1` and the `router-nix.lan` DNS name). To revive
  the router as a real host you'd give it its own entry again.

## Revival steps
1. `git mv` the three trees back to their original paths (see above).
2. Restore the three flake/topology edits listed above.
3. Note: the LXC's `imports = [ ./base … ]` and the `.sops.yaml` creation-rule paths for
   `router-nix.yaml` only resolve once the files are back at their original locations.
