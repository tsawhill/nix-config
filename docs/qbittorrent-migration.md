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
# One key per seeding tier, not per tracker. The value is one or more
# announce-URL substrings, pipe-delimited with no spaces, e.g.
# "flacsfor.me|gazellegames.net". Anything not listed falls through to the
# catch-all tier, which stops seeding and removes the torrent.
qbit_tracker_t1: "KEYWORDS"   # seed forever
qbit_tracker_t2: "KEYWORDS"   # seed 30 days, then remove
qbit_tracker_t3: "KEYWORDS"   # seed 2 days, then remove
```

The qui session secret encrypts the stored qBittorrent credentials in qui's
database. Rotating it deregisters every instance — treat it as permanent.

Encryption targets: each `qbit-*-vpn.yaml` goes to build-nix, its own host, and
`networking-vpn-out-eu1-nix` (which renders the DNAT rule from the placeholder).
`qui_session_secret.yaml` goes to build-nix and `qui-nix`, `qbit-trackers.yaml` to
build-nix and `qbit-lts-nix`.

### Web UI access

Username and password are both declarative, so anything set through the web UI
is wiped on the next service start — the config is reinstalled from the store
every time. `webuiUsername = "taylor"` lives in each host file; the password hash
comes from SOPS and is substituted into the installed config by an `ExecStartPre`
(qBittorrent has no `QBT_WEBUI_PASSWORD`, so it cannot come from the environment).

`authSubnetWhitelist` additionally covers `arrs-nix`, `qui-nix` and Taylor's
machines on LAN and WireGuard, which reach the UI without authenticating. The
password is for everything else. The qBittorrent UIs have no public vhost; qui
behind Authentik is the front door.

Each host has its own password. Read each hash back out **before the service
restarts**, since that is the only place it exists:

```
ssh root@qbit-gen-nix.lan 'grep Password_PBKDF2 /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf'
ssh root@qbit-lts-nix.lan 'grep Password_PBKDF2 /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf'
```

```
sops modules/secrets/server/LXCs/qbittorrent_webui.yaml
```
```yaml
password_gen: "@ByteArray(SALT:HASH)"   # from qbit-gen-nix
password_lts: "@ByteArray(SALT:HASH)"   # from qbit-lts-nix
```

### 5. Gateway and enable

Add both IPs to `clientAddresses` and both `portForwards` entries in
`hosts/server-nix/LXCs/networking-vpn-out-eu1.nix`, keeping Deluge's through the
overlap, and enable `my.secrets.qbit-gen-vpn` / `qbit-lts-vpn` there. Deploy the
gateway, then flip `vpnClientEnabled = true` in both qBittorrent host files and
deploy them, then `qui-nix`, then `local-nginx-nix`.

### 6. Config keys — verified 2026-09-19

Checked against the rendered config on both containers. All tuning keys applied.

Resolved:

- `Network\PortForwardingEnabled` — **confirmed**, lives in `[Network]` and
  persists as `false`. UPnP/NAT-PMP are off.
- `Session\Port` — **confirmed working**. `QBT_TORRENTING_PORT` is honoured: the
  listening TCP/UDP port matches the firewall rule, which reads the secret by a
  separate path. Note `ss` shows the process as `.qbittorrent-no` (systemd
  truncates it), so grepping for `qbittorrent-nox` finds nothing and looks like a
  failure when it is not.
- `Preferences\WebUI\ServerDomains` — key name is right, but the value is a plain
  INI string where **`;` begins a comment**, so only the first entry survives. It
  is also split on `;`, not commas (`AuthSubnetWhitelist` is a Qt QStringList and
  *is* comma-separated — the two differ). Keep it to a single hostname.
  `validateHostHeader` matches the Host against the local address before
  consulting the list, so requests by IP need no entry — but `localhost` is a
  name, not an address, and **is** rejected. That is why qbit-manage connects to
  `127.0.0.1:8080` rather than `localhost:8080`.
- `Session\ShareLimitAction` is the real key, **not** `MaxRatioAction`. String
  values, default `Stop`.
- `Session\AddTorrentStopped`, **not** `AddTorrentPaused`.
- `Meta\MigrationVersion=8` does appear, and is now pinned in `serverConfig`.
  Without it, migrations re-run every boot against an already-current file.
- `SendBufferWatermark`, `SocketBacklogSize`, `ConnectionSpeed`, `FilePoolSize`,
  `AsyncIOThreadsCount`, `HashingThreadsCount` all applied verbatim.
- `WebUI\Password_PBKDF2` is rendered with the section prefix, so the injection
  must match `^WebUI.Password_PBKDF2=`. Matching `^Password_PBKDF2=` silently
  does nothing and leaves the placeholder as the password.

Still unverified, because nothing sets them yet:

- `SendBufferLowWatermark`, `SendBufferWatermarkFactor`, `MemoryWorkingSetLimit`,
  `GlobalMaxInactiveSeedingMinutes` — not currently in either profile.
- `categories.json` schema — check whether newer builds add `download_path` and
  `use_download_path` once categories are in use.

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

Per-tracker seeding policy comes from qbit-manage on `qbit-lts-nix`, since
qBittorrent itself has only global and per-torrent share limits. It runs against
`localhost:8080` with no credentials (`LocalHostAuth` is off).

Promotion to `qbit-lts-nix` is universal — the On Import script runs regardless
of tracker — so the tiers only govern how long a torrent seeds once it arrives:

| Tier | Seeds for | At expiry |
|---|---|---|
| `t1` | forever | nothing |
| `t2` | 30 days | torrent removed, download copy freed |
| `t3` | 2 days | torrent removed, download copy freed |
| unmatched | until the next run | stopped **and removed** |

Unlisted trackers stop and are cleaned up: `max_seeding_time = 0` is an
immediately-met limit, with `share_limit_action = "Stop"` and
`resume_torrent_after_change = false` (the default `true` would undo the stop on
the following run). Cleanup is justified because everything the promotion script
puts here arrived via an *arr import, so the library already holds the media and
the download copy is a seeding artifact.

**"Immediately" is bounded by the timer**, which is why it runs hourly rather
than daily. An unmatched torrent can still seed for up to an hour before being
stopped. Tightening that further means a more frequent timer, not a config
change.

### Two ways a torrent reaches qbit-lts without an import

The cleanup justification above holds for the promotion path. It does **not**
hold for:

1. **The Deluge migration.** The ~950 albums in `/mnt/downloadSSD/Seeding` are
   added to `qbit-lts` directly, not through an *arr. Some may never have been
   imported by Lidarr at all, in which case that copy is the only copy.
2. **Anything you promote by hand** in qui from `qbit-gen`.

For both, a tracker keyword that fails to match means the torrent is stopped and
removed on the next hourly run. The recycle bin gives 30 days and keeps the
`.torrent`, so it is recoverable — but it is the only thing standing between a
typo and real deletion.

**Hard ordering rule: do not set `dryRun = false` until the migration is complete
and a dry-run shows every migrated torrent in the tier you expect.** Anything
falling through to `other` is a keyword that did not match. On a private tracker
that is also how you collect a hit-and-run, so this pass is not optional.

Removal goes through qbit-manage's recycle bin at `/mnt/downloadHDD/.RecycleBin`
with `save_torrents` on, so both the data and the `.torrent` survive for 30 days
before real deletion. That matters because those `.torrent` files are the only
copy of their passkeys.

Tracker keywords are SOPS secrets; the tiers that consume them live in
`hosts/server-nix/LXCs/qbit-lts.nix` where they can be reviewed. A tier's secret
value is one or more announce-URL substrings, pipe-delimited with no spaces:

```yaml
qbit_tracker_t1: "flacsfor.me|gazellegames.net"
```

`tag_update` applies the tracker tags and `share_limits` then filters on them —
both must stay enabled or the groups match nothing.

`my.services.qbit-manage.dryRun` starts **true**. Run it once and read the whole
output: confirm each torrent lands in the tier you expect, that the keywords
matched rather than everything falling through to `other`, and that the only
things marked for removal are ones you actually want gone. Only then set
`dryRun = false`.

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
