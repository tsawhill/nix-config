# Replacing deluge-nix with qbit-gen, qbit-lts and qui

Supersedes `airvpn-eu-deluge.md` once `deluge-nix` is decommissioned.

## Shape

| Host | Role |
|---|---|
| `qbit-gen-nix` (10.73.73.22) | Intake. Every *arr grab and manual one-off lands here. In-flight downloads and anything that failed to import stay here. |
| `qbit-lts-nix` (10.73.73.23) | Long-term seeding. Torrents arrive only after an *arr reports a successful import. Per-tracker share limits live here. |
| `qui-nix` (10.73.73.24) | One web UI over both, at `qbit.tsawhill.org` behind Authentik. |

Both qBittorrent containers egress the Swiss gateway `networking-vpn-out-eu1-nix`
and mount both download pools. The pool a torrent lands in is chosen at download
time by its category: Lidarr on `downloadSSD`, Sonarr/Radarr/general on
`downloadHDD`. **Promotion never moves bytes** — `qbit-lts-nix` adopts each
torrent at its existing path.

Config is fully declarative: `services.qbittorrent` reinstalls `qBittorrent.conf`
on every service start, so web UI preference edits revert. Torrents, resume data
and categories survive.

## Remaining rollout

Stage 1 (modules, host files, registry entries) is committed. What follows still
needs doing, in order.

### 2. Network

Add OPNsense DHCP reservations before creating anything — `nixos-factory` aborts
if a guest does not get its declared address.

| Host | IP | MAC |
|---|---|---|
| `qbit-gen-nix` | 10.73.73.22 | `02:5f:6e:64:81:16` |
| `qbit-lts-nix` | 10.73.73.23 | `02:5f:6e:64:81:17` |
| `qui-nix` | 10.73.73.24 | `02:5f:6e:64:81:18` |

Then deploy `adguard-nix` (DNS rewrites come from topology) and `build-nix`
(refreshes nixos-factory's embedded topology).

### 3. Create the containers

On build-nix, `nixos-factory` → create, one host at a time, choosing "use
existing topology". Instance definitions are already in `instances.yaml`, so the
mounts exist on first boot.

### 4. Secrets

Reserve **two** new forwarded ports on the EU gateway's AirVPN device (remote
port = local port). Do not reuse `deluge_vpn_port`: the gateway asserts
`lib.unique portForwardKeys`, so a duplicate `portSecret` fails evaluation while
Deluge is still up.

Generate the web UI password hash — either with
<https://codeberg.org/feathecutie/qbittorrent_password>, or by starting one
container without a password, setting one in the web UI, and copying the
`Password_PBKDF2` line out of
`/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf`.

Add the `.sops.yaml` creation rules now that the factory has written each host's
age anchor, then fill in the values:

```
sops modules/secrets/server/LXCs/qbit-gen-vpn.yaml
```
```yaml
forwarded_port: "PORT_FROM_AIRVPN"
```

```
sops modules/secrets/server/LXCs/qbit-lts-vpn.yaml
```
```yaml
forwarded_port: "PORT_FROM_AIRVPN"
```

```
sops modules/secrets/server/LXCs/qbittorrent_webui.yaml
```
```yaml
password_pbkdf2: "@ByteArray(SALT:HASH)"
```

```
openssl rand -hex 32
sops modules/secrets/server/LXCs/qui_session_secret.yaml
```
```yaml
session_secret: "HEX_FROM_ABOVE"
```

```
sops modules/secrets/server/LXCs/qbit-trackers.yaml
```
```yaml
# Announce-URL keywords qbit-manage matches on; pipe-delimit aliases.
qbit_tracker_t1: "KEYWORD_FOR_TIER1"
qbit_tracker_t2: "KEYWORD_FOR_TIER2"
```

The qui session secret encrypts the stored qBittorrent credentials in qui's
database. Rotating it deregisters every instance — treat it as permanent.

Encryption targets: each `qbit-*-vpn.yaml` goes to build-nix, its own host, and
`networking-vpn-out-eu1-nix` (which renders the DNAT rule from the placeholder).
`qbittorrent_webui.yaml` goes to build-nix and both qBittorrent hosts,
`qui_session_secret.yaml` to build-nix and `qui-nix`, `qbit-trackers.yaml` to
build-nix and `qbit-lts-nix`.

### 5. Gateway and enable

Add both IPs to `clientAddresses` and both `portForwards` entries in
`hosts/server-nix/LXCs/networking-vpn-out-eu1.nix`, keeping Deluge's through the
overlap, and enable `my.secrets.qbit-gen-vpn` / `qbit-lts-vpn` there. Deploy the
gateway, then flip `vpnClientEnabled = true` in both qBittorrent host files and
deploy them, then `qui-nix`, then `local-nginx-nix`.

### 6. Verify the config keys before loading torrents

Several `Session\*` key names were taken from the 5.2.2 source but not confirmed
against a running binary. On `qbit-gen-nix`, set each in the web UI and read
`/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf` back:

- `SendBufferLowWatermark`, `SendBufferWatermarkFactor`
- `MemoryWorkingSetLimit` (name and unit)
- `GlobalMaxInactiveSeedingMinutes`
- `MaxRatioAction` vs `ShareLimitAction`
- `Network\PortForwardingEnabled` — **confirm this one first.** If it is not the
  UPnP/NAT-PMP toggle, UPnP stays on behind the VPN.
- `Preferences\WebUI\ServerDomains`
- `Meta\MigrationVersion` — qBittorrent 5 may re-run config migrations on every
  boot since the config is reinstalled. Pin it if it appears.
- `categories.json` schema — newer builds may write `download_path` and
  `use_download_path` per entry.

### 7. Monitoring and qui instances

Add `qui` to `defaultServices` in `modules/monitoring/homepage.nix` and to
`defaultServiceChecks` in `modules/monitoring/metrics.nix` — Glance and Gatus are
separate catalogues, so both need an entry. Add the two LAN-only web UI links to
`defaultInternalLinks`. Enable `proxy.qui` in `local-nginx.nix`. Do this only
once qui is actually serving, or Gatus will alert on a 502 vhost.

Then register the instances in qui.

Manual, by design: qui stores instances in SQLite with no declarative path.
Because `AuthSubnetWhitelist` covers `qui-nix`, any credentials work.

| Name | URL |
|---|---|
| `intake` | `http://qbit-gen-nix.lan:8080` |
| `seeding` | `http://qbit-lts-nix.lan:8080` |

### 8. Repoint the *arrs

All four point at **`qbit-gen-nix.lan:8080` only** — `qbit-lts-nix` is never a
download client. Blank username and password (the whitelist covers `arrs-nix`),
Content Layout = Original.

| App | Category |
|---|---|
| Sonarr | `sonarr` |
| Radarr | `radarr` |
| Lidarr | `lidarr` |
| Prowlarr | `prowlarr` |

Per app:

1. Add the qBittorrent client, set its priority to 1 and Deluge's to 50 so new
   grabs route to qBittorrent while Deluge still reports its queue.
2. Clear the Deluge-era "Completed Directory" override. qBittorrent has no such
   field; `categories.json` is the single source of truth now.
3. **Disable "Remove Completed Downloads"** — `qbit-lts-nix` owns retention.
4. Add a Custom Script connection on **On Import** pointing at
   `/run/current-system/sw/bin/qbit-promote`.
5. Delete the Deluge client once the queue has drained.

No remote path mappings are needed: the mounts are at identical paths in every
container.

## Migration of the existing torrents

**Back up `/root/.config/deluge/state/` first.** Deluge runs with
`copy_torrent_file: false`, so those 1261 files are the only copy of the
private-tracker passkeys. Re-add from these files, never from magnet links.

Export metadata via Deluge's JSON-RPC on 8112 from build-nix (`auth.login` →
`web.get_hosts` → `web.connect` → `core.get_torrents_status` for `name`,
`save_path`, `label`, `progress`, `state`), and rsync the state directory down.

Route by lifecycle, not content:

| Condition | Target |
|---|---|
| complete and seeding | `qbit-lts-nix` |
| incomplete, errored, or downloading | `qbit-gen-nix` |

Add each at its Deluge `save_path` verbatim, with the label as `category`,
`contentLayout=Original`, `skip_checking=false`, `stopped=true`, and —
**critically — `autoTMM=false`**. With Automatic Torrent Management on,
qBittorrent relocates the files instead of seeding them in place.

Start in batches of ~25, waiting for each to finish checking. Raise
`MaxActiveCheckingTorrents` temporarily if the recheck is the bottleneck.
Anything left below 100% is almost always a per-torrent rename Deluge kept in
fastresume data, which `core.get_torrents_status` does not expose; fix with "Set
location" or a rename, then force-recheck.

Cut over by parallel drain, not a hard switch: Deluge keeps its port and keeps
seeding untouched. Prove `qbit-gen-nix` on live grabs first and migrate the seed
set last, then stop `deluged` but leave the container for another week.

## qbit-manage

Per-tracker ratio and seed time come from qbit-manage on `qbit-lts-nix`, since
qBittorrent has only global and per-torrent share limits. It runs against
`localhost:8080` with no credentials (`LocalHostAuth` is off).

Tracker keywords are SOPS secrets; the share limit groups that consume them live
in `hosts/server-nix/LXCs/qbit-lts.nix` where they can be reviewed. `tag_update`
applies the tracker tags and `share_limits` then filters on them — both must stay
enabled or the groups match nothing.

`my.services.qbit-manage.dryRun` starts **true**. Run it once and read the whole
output: confirm each torrent lands in the group you expect, that the keywords
actually matched rather than everything falling through to `other`, and that
nothing is reported as removable. Only then set `dryRun = false`.

`cleanup` stays `false` in every group and `share_limit_action` stays at its
default. This instance holds torrents whose `.torrent` files are the only copy of
their passkeys.

## Decommissioning deluge-nix

1. Stop `deluged` and `deluge-web`; observe for a week.
2. Remove the Deluge download client from all four *arrs.
3. Drop `deluge-nix` from `clientAddresses` and `portForwards` on the gateway and
   remove `my.secrets.deluge-vpn.enable` there; deploy the gateway.
4. Delete `modules/software/services/deluge.nix`,
   `hosts/server-nix/LXCs/deluge.nix`,
   `modules/secrets/server/LXCs/deluge-vpn.{nix,yaml}`,
   `pkgs/vpn-egress/deluge_port.py` and `test_deluge_port.py`, and the
   `deluge-nix` entries in `colmena.nix`, `topology.nix` (both `hostDefinitions`
   and `incusGuestNames`), `instances.yaml` and `.sops.yaml`.
5. `nixos-factory` → delete `deluge-nix`; check `/mnt/nix-stores/deluge-nix` is
   reclaimed.
6. Release the old AirVPN port reservation.
7. Promote the three new hosts from tag `null` to `"weekly"` in `colmena.nix`.
