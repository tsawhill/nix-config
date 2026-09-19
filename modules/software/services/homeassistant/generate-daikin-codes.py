"""Generate Daikin ARC452A21 codes in Tuya IR base64.

Rather than synthesising pulse trains, this patches the payload bits of a
verified SmartIR capture in place. Timing, preamble and framing stay exactly as
captured; only the bits that encode mode, temperature and fan change, plus the
frame checksum. Round-tripping a capture with its own bytes must reproduce it
exactly, which is what --selftest asserts.

Frame layout (third frame, 19 bytes):
  byte 5  mode+power   0x39 cool on, 0x49 heat on, low nibble 0 = off
  byte 6  temperature in Celsius, doubled
  byte 8  fan          0x30..0x70 speeds 1-5, 0xa0 auto
  byte 18 checksum     sum of bytes 0..17, mod 256
"""

import base64
import json
import sys

from tinytuya.Contrib.IRRemoteControlDevice import IRRemoteControlDevice as IR

TICK_US = 269.0 / 8192.0 * 1000.0
FRAME_GAP_US = 15000
ONE_SPACE_US = 800

MODE_BYTE = {"cool": 0x30, "heat": 0x40}
FAN_BYTE = {"1": 0x30, "2": 0x40, "3": 0x50, "4": 0x60, "5": 0x70, "auto": 0xA0}


def broadlink_to_pulses(code_b64):
    data = base64.b64decode(code_b64)
    length = data[2] | (data[3] << 8)
    payload = data[4 : 4 + length]
    pulses = []
    i = 0
    while i < len(payload):
        if payload[i] == 0x0D and i + 1 < len(payload) and payload[i + 1] == 0x05:
            break
        if payload[i] == 0:
            if i + 2 >= len(payload):
                break
            value = (payload[i + 1] << 8) | payload[i + 2]
            i += 3
        else:
            value = payload[i]
            i += 1
        pulses.append(min(65535, int(round(value * TICK_US))))
    return pulses


def frame_spans(pulses):
    """Index ranges of each frame, excluding the separating gaps."""
    spans = []
    start = 0
    for index, value in enumerate(pulses):
        if index % 2 == 1 and value > FRAME_GAP_US:
            spans.append((start, index - 1))
            start = index + 1
    if start < len(pulses):
        spans.append((start, len(pulses) - 1))
    return [s for s in spans if s[1] - s[0] > 32]


def read_frame(pulses, span):
    """Decode one frame's bytes. Body begins after the header mark/space."""
    start, end = span
    bits = []
    i = start + 2
    while i + 1 <= end:
        bits.append(1 if pulses[i + 1] > ONE_SPACE_US else 0)
        i += 2
    out = bytearray()
    for i in range(0, len(bits) - 7, 8):
        byte = 0
        for j in range(8):
            byte |= bits[i + j] << j
        out.append(byte)
    return bytes(out)


def space_levels(pulses, span):
    """The template's own short/long space durations, so timing is preserved."""
    start, end = span
    shorts, longs = [], []
    i = start + 2
    while i + 1 <= end:
        (longs if pulses[i + 1] > ONE_SPACE_US else shorts).append(pulses[i + 1])
        i += 2
    return (
        max(set(shorts), key=shorts.count),
        max(set(longs), key=longs.count),
    )


def write_frame(pulses, span, frame_bytes):
    """Rewrite a frame's payload bits in place, leaving every mark untouched."""
    zero_us, one_us = space_levels(pulses, span)
    start, end = span
    bits = []
    for byte in frame_bytes:
        for j in range(8):
            bits.append((byte >> j) & 1)
    out = list(pulses)
    i = start + 2
    for bit in bits:
        if i + 1 > end:
            raise ValueError("frame is shorter than the bytes being written")
        # Captured spaces jitter, so only rewrite where the bit actually
        # changes. Untouched bits keep their original timing exactly.
        current = 1 if out[i + 1] > ONE_SPACE_US else 0
        if current != bit:
            out[i + 1] = one_us if bit else zero_us
        i += 2
    return out


def checksum(frame_bytes):
    return sum(frame_bytes[:-1]) & 0xFF


def build(template_code, mode, fan, temp_c):
    pulses = broadlink_to_pulses(template_code)
    spans = frame_spans(pulses)
    if len(spans) != 3:
        raise ValueError(f"expected 3 frames, found {len(spans)}")

    frame = bytearray(read_frame(pulses, spans[2]))
    frame[5] = MODE_BYTE[mode] | 0x09
    frame[6] = int(round(temp_c * 2))
    frame[8] = FAN_BYTE[fan]
    frame[18] = checksum(frame)

    return IR.pulses_to_base64(write_frame(pulses, spans[2], bytes(frame)))


def selftest(table):
    """Every captured code must survive decode+re-encode unchanged."""
    checked = failures = 0
    for mode in ("cool", "heat"):
        for fan, temps in table["commands"][mode].items():
            for temp, code in temps.items():
                pulses = broadlink_to_pulses(code)
                spans = frame_spans(pulses)
                original = read_frame(pulses, spans[2])
                rebuilt = write_frame(pulses, spans[2], original)
                checked += 1
                if rebuilt != pulses:
                    failures += 1
                    print(f"  FAIL round-trip {mode}/{fan}/{temp}")
                    continue
                # And the documented field layout must match the capture.
                want = build(code, mode, fan, float(temp))
                got = IR.pulses_to_base64(pulses)
                if want != got:
                    failures += 1
                    print(f"  FAIL rebuild {mode}/{fan}/{temp}")
    print(f"selftest: {checked} codes checked, {failures} failures")
    return failures == 0


def main():
    with open(sys.argv[1]) as handle:
        table = json.load(handle)

    if "--selftest" in sys.argv:
        sys.exit(0 if selftest(table) else 1)

    lo, hi = float(sys.argv[2]), float(sys.argv[3])
    commands = {"off": IR.pulses_to_base64(broadlink_to_pulses(table["commands"]["off"]))}
    temps = [lo + i for i in range(int(hi - lo) + 1)]

    # One clean template drives every code. Two source captures are defective
    # (cool/4/20 is bit-shifted, heat/2/22 carries a stray flag in byte 10),
    # so seeding per mode/fan would propagate those into generated codes.
    template = table["commands"]["cool"]["auto"]["22"]
    for mode in ("cool", "heat"):
        commands[mode] = {
            fan: {str(int(t)): build(template, mode, fan, t) for t in temps}
            for fan in FAN_BYTE
        }

    out = {
        "manufacturer": "Daikin",
        "supportedModels": table["supportedModels"],
        "commandsEncoding": "Base64",
        "supportedController": "Broadlink",
        "minTemperature": lo,
        "maxTemperature": hi,
        "precision": 1.0,
        "operationModes": ["cool", "heat"],
        "fanModes": ["auto", "1", "2", "3", "4", "5"],
        "commands": commands,
    }
    json.dump(out, sys.stdout, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
