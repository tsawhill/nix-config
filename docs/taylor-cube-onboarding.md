# Onboarding `taylor-cube-nix` (Valve Steam Machine) to the fleet

> Runbook for adding the incoming **Valve Steam Machine 512GB** to this nix-config fleet as
> `taylor-cube-nix`. It should behave like the Steam Deck: **boot straight into the Steam Big
> Picture / Game Mode (gamescope) session, with a "Switch to Desktop" option into KDE Plasma.**
>
> Split into **Phase A** (config we can write/commit before the machine arrives) and **Phase B**
> (the short install-time checklist that needs the real hardware). Nothing here is applied to a
> host until Phase B.

## Background

The behavior we want is entirely provided by **Jovian-NixOS** (`jovian.steam.autoStart = true`
+ `jovian.steam.desktopSession = "plasma"`), exactly as the Deck does it today in
`hosts/taylor-deck-nix/default.nix`. The cleanest template is the whole `hosts/taylor-deck-nix/`
directory.

The Steam Machine is a console-style **AMD Zen4 + RDNA3 APU** PC — **not** Deck hardware — so
vs the Deck config:

- **Drop** `jovian.devices.steamdeck` (Deck-only APU/controls/fan/backlight support).
- **Leave `software.games.gamescope.resolutions` unset** (default `[ ]`). That option only
  generates *per-game launcher variants* at fixed render resolutions for this repo's custom game
  library (the Deck pins `[1280x800]`); it does **not** set the Big Picture session output. Unset
  ⇒ no fixed-res launcher variants, and the gamescope session negotiates output from the TV's
  EDID at runtime — so there is nothing to configure for display resolution.
- Generic AMD hardware config (its own disk UUIDs, initrd modules — from `nixos-generate-config`).
- Its own identity everywhere: topology entry, colmena node, secrets, SSH trust.

**Game storage** — "both": mount the NAS `//samba-nix/gameSSD` share at `/mnt/gameSSD` (like the
Deck) **and** keep select titles on the local 512GB SSD via `software.games.localGames`.

### Allocations (chosen)

| Item | Value |
| --- | --- |
| Hostname | `taylor-cube-nix` |
| DHCP short name | `cube-nix` |
| LAN IP | `10.73.73.74` |
| WireGuard IP | `10.50.50.6` |
| Samba account | `cube8801` (new per-device account; see §A7) |
| Syncthing device | `cube` |

---

## Phase A — Scaffold (can be done before the machine arrives)

### A1. New host directory `hosts/taylor-cube-nix/`

Copy `hosts/taylor-deck-nix/` and adjust:

**`default.nix`** (from `hosts/taylor-deck-nix/default.nix`):

- `networking.hostName = "taylor-cube-nix";`
- Keep `nixpkgs.config.permittedInsecurePackages = [ "pnpm-9.15.9" ]` (same software set as the Deck).
- Keep the Jovian import and the **KDE-only** desktop imports (`modules/software/desktop/kde.nix`
  + `modules/software/desktop/pipewire/base.nix`). Do **not** import the full
  `modules/software/desktop` dir — it auto-imports SDDM, which conflicts with Jovian `autoStart`.
- `jovian` block: keep `steam.{enable, autoStart, user = "taylor", desktopSession = "plasma"}`
  and `decky-loader.enable`. **Remove** the `devices.steamdeck` block. Leave
  `jovian.steamos.useSteamOSConfig` at its default (`true` = the SteamOS/neptune kernel). Add a
  comment: set it to `false` if the SteamOS kernel misbehaves on the cube's APU — that's the one
  Jovian setting with real non-Deck hardware risk.
- Keep the full `software.apps.*` toggles and `software.games.steamSync.stopSteamDuringSync = true`.
- **Omit** the `software.games.gamescope.resolutions` block → it stays at its default `[ ]`
  (see Background; this is not a display-output setting).
- Keep `software.games.localGames = [ ];` scaffold (add entry ids as games are copied to local disk).
- Point the secret enables at the cube's names:
  - `my.secrets.sshclientkey.taylor-cube-nix-taylor.enable = true;`
  - `my.secrets.wireguard.pubkeys.enable = true;`
  - `my.secrets.wireguard.taylor-cube-nix.wg-remote.enable = true;`
  - `my.secrets.steamgriddb_api_key.enable = true;`
  - the samba account enable (see A7 — `my.secrets.cube8801-pass.enable = true;`).
- Update the SSH pubkey imports as desired: `build-nix-root` is required (so `build-nix` can
  deploy); desktop/laptop/phone are optional, same as the Deck.

**`home-manager.nix`** — copy `hosts/taylor-deck-nix/home-manager.nix` **verbatim** (host-agnostic;
the `Unit.Before = [ "gamescope-session.service" ]` ordering for `fetch-game-art` /
`sync-steam-shortcuts` matters here too, since Steam owns `shortcuts.vdf` once Game Mode starts).

**`system/hardware/default.nix`** — copy the Deck's (imports `not-detected.nix` + `./cpu.nix`).

**`system/hardware/cpu.nix`** — copy the Deck's (AMD: `hardware.enableRedistributableFirmware`,
`hardware.cpu.amd.updateMicrocode`, `boot.kernelModules = [ "kvm-amd" ]`).

> Optional / deferrable: add a `gpu.nix` + LACT later for fan/power control. Not needed for the
> boot-to-Big-Picture goal — the gaming bundle already provides `hardware.graphics` + 32-bit mesa.

**`system/boot.nix`** — copy the Deck's (systemd-boot UEFI, `canTouchEfiVariables = true`). The
`boot.initrd.availableKernelModules` list is a **Phase-B placeholder** — replace with
`nixos-generate-config`'s output from the real machine.

**`system/disks.nix`** — `fileSystems."/"` (ext4) + `/boot` (vfat) with **placeholder
`by-uuid` values** (filled in Phase B). Drop the Deck's SD-card mount (the cube has no SD slot;
local games live on the root disk). `swapDevices = [ ];`.

**`system/networking.nix`** — copy the Deck's (NetworkManager, bluetooth, `my.network.wg-remote`
back to the home LAN); change every `taylor-deck-nix` reference to `taylor-cube-nix`. Leave the
AirVPN block commented, like the Deck.

> `wg-remote` is unnecessary on an always-home box but harmless, and kept for consistency with
> desktop/laptop/deck.

**`system/samba.nix`** — copy the Deck's, but with a **new per-device Samba credential** (mirrors
the fleet pattern: desktop=`immobile0783`, laptop=`umbriel`, deck=`pelican8334`). Use account
`cube8801`:

- `credentialsPath = "/run/secrets/smb-cube-credentials"`
- `my.secrets.cube8801-pass.enable = true;` (+ the `neededForUsers = lib.mkForce false;` line)
- `sops.templates."smb-cube-credentials"` with `username=cube8801` / `domain=taylor-home` /
  `password=${config.sops.placeholder."cube8801-pass"}`
- Mount stays `//samba-nix/gameSSD` at `/mnt/gameSSD` with the same lazy-automount options.

> Alternative (avoids a server-side change): reuse the Deck's `pelican8334` account by adding
> `taylor-cube-nix` as a recipient to its existing secret. Simpler, but two machines then share
> one credential. **Recommendation: new account.**

**`system/syncthing.nix`** — copy the Deck's; `device = "cube"`,
`credentialsFile = "${self}/modules/secrets/syncthing/taylor-cube-nix.yaml"`. Joins the
`gamesaves` share (auto-activates emulator-save syncing). Do **not** join `roms` (too large for
local disk).

### A2. Topology — `modules/network/topology.nix`

Add under `hosts`:

```nix
taylor-cube-nix = {
  lan = {
    ip = "10.73.73.74";
    mac = "TODO:fill-real-NIC-mac-at-install";   # Phase B — needed for the router's DHCP lease
    dhcpHostname = "cube-nix";
  };
  wgRemote.ip = "10.50.50.6";
  dns.enable = true;
};
```

### A3. Colmena node — `flake-outputs/colmena.nix`

- Add the node next to the deck line (~L168). **Register it manual-only (`tag = null`) during
  Phase A** so the automated daily pre-deploy doesn't try to build/reach a machine that doesn't
  exist yet; flip to `"daily"` in Phase B once it's installed:

  ```nix
  "taylor-cube-nix" = mkUnstableHost null "taylor-cube-nix" "${self}/hosts/taylor-cube-nix";
  ```

- `meta.nodeNixpkgs`: add `"taylor-cube-nix" = unstablePkgs;`
- `meta.nodeSpecialArgs`: add `"taylor-cube-nix" = unstableArgs;`

### A4. First-install output — `flake.nix` (~L106–125)

Add an inline `nixosConfigurations.taylor-cube-nix` block, copied verbatim from the
`taylor-deck-nix` block, so the machine can be first-installed with
`nixos-install --flake .#taylor-cube-nix`. (The `jovian` input is already present — `flake.nix` ~L80.)

### A5. SSH trust

- Create `modules/ssh/pubkeys/taylor-cube-nix-taylor.nix` (copy an existing pubkey module). Its
  actual public key is filled in Phase B; import it into other hosts only if you want to SSH
  *from* the cube into them.
- `modules/ssh/known_hosts` — the `taylor-cube-nix.lan ssh-ed25519 …` line is added in **Phase B**
  (after first boot generates the host key) so `build-nix` can deploy non-interactively.

### A6. Secrets — definition files

> Repo policy: never run `sops` / read secrets from an agent. For each encrypted `.yaml` below,
> the operator runs `sops` by hand (a plaintext template + exact command is provided at
> implementation time).

Create these secret **definition** modules by copying the Deck's equivalents:

- `modules/secrets/ssh/client_keys/taylor-cube-nix-taylor.{nix,yaml}`
- `modules/secrets/wireguard/taylor-cube-nix/{default.nix,wg-remote.nix}` + `wg-remote.yaml`
- `modules/secrets/syncthing/taylor-cube-nix.yaml`
- `modules/secrets/server/LXCs/samba/cube8801.{nix,yaml}` (new Samba account)

`.sops.yaml` edits:

- **Anchor** under `# Personal machines`: `- &taylor-cube-nix ageTODO…` (the age key is derived
  from the host's ed25519 key in Phase B; leave a clearly-marked placeholder until then).
- **New `creation_rules`**, each `key_groups: [ { age: [ *build-nix, *taylor-cube-nix ] } ]`:
  - `modules/secrets/ssh/client_keys/taylor-cube-nix-taylor.yaml`
  - `modules/secrets/wireguard/taylor-cube-nix/wg-remote.yaml`
  - `modules/secrets/syncthing/taylor-cube-nix.yaml`
- **Samba** rule `modules/secrets/server/LXCs/samba/cube8801.yaml` =
  `[ *build-nix, *samba-nix, *taylor-cube-nix ]`.
- **Add `*taylor-cube-nix`** to the two shared multi-host rules:
  `modules/secrets/wireguard/pubkeys.yaml` and
  `modules/secrets/steamgriddb/steamgriddb_api_key.yaml`. These must be **re-encrypted** with
  `sops updatekeys <file>` after the recipient is added (Phase B, once the real age key exists).

### A7. Samba server-side (if using the new `cube8801` account)

Add the `cube8801` Samba user + `gameSSD` share access on **samba-nix**, mirroring `pelican8334`
in `hosts/server-nix/LXCs/samba.nix`. (Skip if reusing `pelican8334`.)

### A8. Build-verify Phase A (no hardware needed)

After staging the new files (`git add`), build-only on the build server:

```
colmena build --on taylor-cube-nix --impure
```

This confirms the whole config evaluates and builds. It requires the secret `.yaml` files to
exist first (even as encrypted placeholders), since sops-nix references them at eval time. Do
**not** run a local `nix eval` — it hangs on this box.

---

## Phase B — Install-time checklist (when the machine arrives)

1. Boot the NixOS installer; run `nixos-generate-config` → copy the real `fileSystems` UUIDs into
   `hosts/taylor-cube-nix/system/disks.nix` and the real `initrd.availableKernelModules` into
   `system/boot.nix`.
2. Read the NIC MAC → fill `taylor-cube-nix.lan.mac` in `modules/network/topology.nix` (and add a
   DHCP reservation on the router if that's how the fleet pins leases).
3. `nixos-install --flake .#taylor-cube-nix`; set the `taylor` password; reboot → it should land
   in Big Picture, with **Steam → Power → Switch to Desktop** dropping into KDE Plasma.
4. Derive the host age key: `ssh-keyscan taylor-cube-nix.lan` (or read
   `/etc/ssh/ssh_host_ed25519_key.pub`) → `ssh-to-age` → paste the `age1…` into the `.sops.yaml`
   anchor. Then re-encrypt the shared secrets: `sops updatekeys` on
   `modules/secrets/wireguard/pubkeys.yaml` and
   `modules/secrets/steamgriddb/steamgriddb_api_key.yaml`, and create/encrypt the cube's own
   secret yamls (`sops` command + template provided at that time).
5. Add the cube's `ssh_host_ed25519_key.pub` line to `modules/ssh/known_hosts`; fill the real
   user pubkey into `modules/ssh/pubkeys/taylor-cube-nix-taylor.nix`.
6. Flip the colmena node's tag from `null` → `"daily"` in `flake-outputs/colmena.nix` so it joins
   the scheduled fleet updates.
7. Hand day-to-day updates to colmena: `deploy taylor-cube-nix` (ask before deploying).

---

## Verification

- **Phase A (no hardware):** `colmena build --on taylor-cube-nix --impure` on the build server —
  confirms the config evaluates and builds (secret `.yaml` placeholders must exist first).
- **Phase B (on the machine):** confirm it boots into gamescope Big Picture; confirm "Switch to
  Desktop" → KDE Plasma and back; confirm `/mnt/gameSSD` automounts on first access; confirm a
  colmena `deploy taylor-cube-nix` succeeds end-to-end.

## Files touched (Phase A + B, for reference)

- **New:** `hosts/taylor-cube-nix/` (`default.nix`, `home-manager.nix`,
  `system/{boot,disks,networking,samba,syncthing}.nix`, `system/hardware/{default,cpu}.nix`),
  `modules/secrets/{ssh/client_keys,wireguard,syncthing,server/LXCs/samba}/…`,
  `modules/ssh/pubkeys/taylor-cube-nix-taylor.nix`
- **Edited:** `flake.nix`, `flake-outputs/colmena.nix`, `modules/network/topology.nix`,
  `.sops.yaml`, `modules/ssh/known_hosts`, `hosts/server-nix/LXCs/samba.nix` (if new Samba account)
