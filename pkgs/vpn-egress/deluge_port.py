#!/usr/bin/env python3
"""Apply a private listen port before Deluge starts, preserving other settings."""

import json
import os
import re
import sys
import tempfile
from pathlib import Path


def configure(path, port_text):
    if not re.fullmatch(r"[0-9]{1,5}", port_text) or not 1 <= int(port_text) <= 65535:
        raise ValueError("Forwarded-port secret must contain one valid port number")
    port = int(port_text)
    if path.exists():
        text = path.read_text().strip()
        decoder = json.JSONDecoder()
        version, offset = decoder.raw_decode(text)
        settings = json.loads(text[offset:])
        if not isinstance(version, dict) or not isinstance(settings, dict):
            raise ValueError("Unexpected Deluge configuration format")
    else:
        version, settings = {"file": 1, "format": 1}, {}
    settings.update(listen_ports=[port, port], random_port=False, upnp=False, natpmp=False)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".core.conf.")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(json.dumps(version, indent=2) + "\n" + json.dumps(settings, indent=2) + "\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]), Path(sys.argv[2]).read_text().strip())
    except (ValueError, OSError):
        # Do not expose the secret or existing config in service logs.
        raise SystemExit("Cannot configure Deluge's private listen port; check secret and core.conf")
