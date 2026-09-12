# glow

A cyan/violet terminal dashboard over real rsync, intended for tmux panes.

```sh
glow -a --partial /source/ /destination/
glow -a --partial /source/ user@host:/destination/
glow -an /source/ /destination/  # ordinary rsync dry run
```

Enabled with `software.glow.enable`; the server CLI bundle enables it by
default (including workstations using the full bundle).

The transfer deck shows the active file and recent completed files, with individual
bars, percentages, and sizes. Rsync transfers files sequentially. The dashboard
retains at most 64 rows and displays up to eight, depending on terminal height.
The header shows logical bytes processed, completed files, elapsed time, rsync's
file speed/ETA, and a sampled throughput sparkline. Logical bytes include data
reconstructed by rsync's delta algorithm; they are not network traffic.

The overall bar is **file-list entries checked**, not bytes or files copied. Its
total can grow while rsync scans. No extra dry run or full directory scan is added.
No-change runs may have no progress counts because rsync emits no file progress.

Pass ordinary rsync arguments, including SSH options, excludes, and bandwidth
limits. No archive, deletion, or partial-file flags are added automatically.
The dashboard overrides output formatting (`--info`, `--out-format`, `--outbuf`,
and human-readable numbers). Dry runs, quiet mode, list-only mode, and redirected
stdout use plain rsync. SSH retains stdin and controlling-terminal access for
authentication; stderr remains visible. Prefer SSH keys for unattended tmux jobs.
Exit codes propagate; Ctrl+C cancels and returns 130.

To run the integration checks with Python, Rich, and rsync available:

```sh
python3 pkgs/glow/test_glow.py
```

Tests use disposable local directories and pseudo-terminals. They do not contact
remote hosts. SSH transfers and deployment still require testing on the target.
