"""Read M7 status without changing mouse settings; empty stdout hides Wayle.

Protocol reference: https://github.com/alexfrih/mchose-linux/blob/main/PROTOCOL.md
Only the identity query (feature report 0x11, command 0x06) is sent.
"""

import fcntl
import json
from pathlib import Path
import sys
import time


DEBUG = "--debug" in sys.argv


def debug(message):
    if DEBUG:
        print(f"MCHOSE battery: {message}", file=sys.stderr)


def decode_status(report):
    if len(report) < 13 or report[:2] != bytes([0x11, 0xF9]):
        return None
    data = bytes(value ^ 0xFF for value in report[2:])
    if int.from_bytes(data[:2], "little") != 0x5253 or data[9] > 100:
        return None
    return bool(data[8] & 8), data[9], data[10]


def read_status(device):
    # Linux HIDIOCSFEATURE/HIDIOCGFEATURE, 21-byte feature report.
    with device.open("r+b", buffering=0) as handle:
        # Avoid overlapping queries from multiple bars/monitors.
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for attempt in range(4):
            request = bytes([0x11, 0xF9] + [0xFF] * 19)
            debug(f"{device}: sending identity query, attempt {attempt + 1}")
            fcntl.ioctl(handle, 0xC0154806, request)
            time.sleep(0.025)
            response = bytearray([0x11] + [0] * 20)
            debug(f"{device}: reading identity reply")
            length = fcntl.ioctl(handle, 0xC0154807, response, True)
            debug(f"{device}: reply {bytes(response[:length]).hex(' ')}")
            status = decode_status(response[:length])
            debug(f"{device}: decoded status {status}")
            if status is not None:
                return status
            time.sleep(0.12 * (attempt + 1))
    return None


def main():
    for node in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        try:
            properties = dict(
                line.split("=", 1)
                for line in (node / "device/uevent").read_text().splitlines()
                if "=" in line
            )
            ids = properties.get("HID_ID", "").split(":")
            debug(f"{node.name}: HID_ID={properties.get('HID_ID', '?')}, "
                  f"name={properties.get('HID_NAME', '?')}")
            if len(ids) != 3 or tuple(int(value, 16) for value in ids[1:]) not in {
                (0x5253, 0x0031), (0x5253, 0x1020)
            }:
                continue
            descriptor = (node / "device/report_descriptor").read_bytes()
            if b"\x06\x01\xff" not in descriptor:
                debug(f"{node.name}: no vendor configuration collection")
                continue
            status = read_status(Path("/dev") / node.name)
            if status is None or not status[0]:
                debug(f"{node.name}: no valid status or mouse offline")
                continue
            _, percentage, charging = status
            print(json.dumps({
                "text": f"{percentage}%" + (" ⚡" if charging else ""),
                "percentage": percentage,
                "tooltip": f"MCHOSE M7: {percentage}%" + (" (charging)" if charging else ""),
            }))
            return
        except (OSError, ValueError) as error:
            print(f"MCHOSE battery: {node.name}: {error}", file=sys.stderr)
    debug("No connected mouse with a valid battery reading found")
    print("")


if __name__ == "__main__":
    main()
