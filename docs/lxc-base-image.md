# LXC base image

Every container `nixos-factory create` provisions starts from two artifacts on
server-nix:

| Artifact | Location | What it is |
| --- | --- | --- |
| Rootfs image | Incus alias `barebones-nixos-allow-keys` | `/`, minus the store |
| Store template | `rpool/VMDisks/nix-templates/nixos-base-nix@ready` | the `/nix` that rootfs boots from |

`create` initialises the container from the image, `zfs send`s the snapshot into
`downloadHDD/nix-stores/<host>`, and mounts it at `/nix`. The container then has
to boot far enough for colmena to SSH in and push the real configuration.

Both artifacts come from one build of `nixosConfigurations.lxc-template`
([hosts/server-nix/LXCs/base/template.nix](../hosts/server-nix/LXCs/base/template.nix)),
so the rootfs and the store it boots from cannot drift apart.

## Refreshing it

Run `nixos-factory` on build-nix and pick `template`. It builds the tarball and
Incus metadata, ships both to server-nix, stages the store on a scratch dataset,
repacks the rootfs without `/nix/store`, and only then swaps the image alias and
dataset in. The previous store is renamed to `…-retired-<timestamp>` and the
previous image is left behind under its fingerprint — destroy both once a real
`create` has succeeded.

The template file has to be committed before this works: `nix build` on a path
flake only sees git-tracked files.

## Keep it on the fleet's nixpkgs

The template is built from `nixpkgs-stable`, the same input
[flake-outputs/colmena.nix](../flake-outputs/colmena.nix) deploys these LXCs
from. That is the whole point of the exercise. When the base drifts a release or
two behind what colmena pushes, the first deploy dies inside
`switch-to-configuration` — the failure surfaces as dbus units refusing to
restart, because the running systemd is older than the one the new closure
expects. Rebuild the template whenever `nixpkgs-stable` moves to a new release.
