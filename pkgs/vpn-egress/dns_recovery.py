#!/usr/bin/env python3
"""Recover a stuck resolver without restarting it throughout an upstream outage."""

import json
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path


def query(config, arguments, name):
    try:
        result = subprocess.run(
            [config["kdig"], *arguments, name, "A", "+timeout=3", "+retry=0"],
            capture_output=True, text=True, timeout=6,
        )
        return result.returncode == 0 and bool(
            re.search(r"status: (NOERROR|NXDOMAIN)\b", result.stdout)
        )
    except subprocess.TimeoutExpired:
        return False


def recover(config, state, *, probe=query, run=subprocess.run, now=time.time):
    # Different names avoid relying on a previously cached positive response.
    names = [f"{uuid.uuid4().hex}.{zone}" for zone in ("example.com", "example.net")]
    local = ["@127.0.0.1", "-p", str(config["port"])]
    if any(probe(config, local, name) for name in names):
        state["failures"] = 0
        return
    state["failures"] = state.get("failures", 0) + 1
    if state["failures"] < 2 or now() - state.get("lastRestart", 0) < 300:
        return
    if not any(probe(config, upstream, name)
               for upstream in config["upstreams"] for name in names):
        print("DNS upstream is unavailable; waiting for connectivity recovery", flush=True)
        return
    state["lastRestart"] = int(now())
    print(f"Upstream recovered but local DNS is failing; restarting {config['service']}", flush=True)
    run([config["systemctl"], "restart", f"{config['service']}.service"],
        check=True, timeout=30)
    if any(probe(config, local, name) for name in names):
        state["failures"] = 0
        print("DNS recovery verified", flush=True)
    else:
        print("DNS still failing; retrying after cooldown", flush=True)


def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    path = Path(config["stateFile"])
    try:
        state = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    try:
        recover(config, state)
    finally:
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(state))
        temporary.replace(path)


if __name__ == "__main__":
    main()
