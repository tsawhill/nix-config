"""Prune missing Nix font registrations before starting an idle Proton prefix."""

import fcntl
import hashlib
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile


def prefix_paths(prefix):
    root = Path(prefix).expanduser().resolve()
    return {root, root / "pfx"}


def active_prefix(paths):
    # Ignore our own launcher ancestry, whose environment may already name the
    # prefix. Inspect only prefix variables; never print process environments.
    ancestors = set()
    pid = os.getpid()
    while pid:
        ancestors.add(pid)
        try:
            status = Path(f"/proc/{pid}/status").read_text()
            pid = int(re.search(r"^PPid:\s+(\d+)", status, re.M)[1])
        except (OSError, TypeError):
            return True
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) in ancestors:
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            entries = (proc / "environ").read_bytes().split(b"\0")
            for entry in entries:
                key, _, value = entry.partition(b"=")
                if key in (b"WINEPREFIX", b"STEAM_COMPAT_DATA_PATH") and value:
                    path = Path(os.fsdecode(value))
                    if not path.is_absolute():
                        path = (proc / "cwd").resolve() / path
                    if path.resolve() in paths:
                        return True
        except FileNotFoundError:
            continue  # Process exited during inspection.
        except OSError:
            return True  # Cannot establish that the prefix is idle.
    return False


def prune(data):
    section = ""
    kept = []
    removed = 0
    for line in data.decode("utf-8", errors="surrogateescape").splitlines(keepends=True):
        if line.startswith("["):
            section = line.split("]", 1)[0][1:].replace("\\\\", "\\")
        # Only Wine's external font cache and Microsoft's font registrations.
        font_section = section in (
            r"Software\Wine\Fonts\External Fonts",
            r"Software\Microsoft\Windows\CurrentVersion\Fonts",
            r"Software\Microsoft\Windows NT\CurrentVersion\Fonts",
            r"Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Fonts",
            r"Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Fonts",
        )
        match = re.fullmatch(r'"(?:[^"\\]|\\.)*"="([Zz]:[^"\r\n]*)"\s*', line) if font_section else None
        if match:
            path = match[1][2:].replace("\\\\", "/")
            if path.startswith("/nix/store/") and not Path(path).exists():
                removed += 1
                continue
        kept.append(line)
    return "".join(kept).encode("utf-8", errors="surrogateescape"), removed


def clean(prefix, state):
    paths = prefix_paths(prefix)
    if active_prefix(paths):
        print("proton-font-guard: prefix in use or unreadable; skipping cleanup", file=sys.stderr)
        return
    root = Path(prefix).expanduser().resolve()
    registry_dir = root / "pfx" if (root / "pfx").is_dir() else root
    changes = []
    for name in ("system.reg", "user.reg"):
        source = registry_dir / name
        if not source.exists() or source.is_symlink():
            continue
        original = source.read_bytes()
        updated, count = prune(original)
        if count:
            changes.append((source, original, updated, count))
    if not changes:
        return
    backup = Path(tempfile.mkdtemp(prefix="backup-", dir=state))
    for source, original, _, _ in changes:
        (backup / source.name).write_bytes(original)
    # Syncthing can update files during inspection. Abort if anything changed.
    if active_prefix(paths) or any(src.read_bytes() != old for src, old, _, _ in changes):
        return
    for source, original, updated, count in changes:
        fd, name = tempfile.mkstemp(prefix=".font-guard-", dir=registry_dir)
        temporary = Path(name)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(updated)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), stat.S_IMODE(source.stat().st_mode))
            if source.read_bytes() != original:
                return
            temporary.replace(source)
            print(f"proton-font-guard: removed {count} stale fonts from {source.name}; backup: {backup}", file=sys.stderr)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    prefix, *command = sys.argv[1:]
    if not command:
        raise SystemExit("Usage: proton-font-guard PREFIX COMMAND [ARGS...]")
    state_home = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    key = hashlib.sha256(os.fsencode(Path(prefix).expanduser().resolve())).hexdigest()[:24]
    state = state_home / "proton-font-guard" / key
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize cleanup through child creation. The next launcher can then see
    # the child's prefix environment even before Wine/UMU finishes starting.
    with (state / "launch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            clean(prefix, state)
        except OSError as error:
            print(f"proton-font-guard: cleanup skipped: {error}", file=sys.stderr)
        child = subprocess.Popen(command)
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda signum, frame: child.send_signal(signum))
    result = child.wait()
    return result if result >= 0 else 128 - result


if __name__ == "__main__":
    sys.exit(main())
