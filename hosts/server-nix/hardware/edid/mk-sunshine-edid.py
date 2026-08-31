"""Build the EDID presented to sunshine-nix on the HDMI dummy plug.

The NVIDIA DRM driver only accepts modes from the pool it derives from a
connector's EDID, so KWin's addCustomMode timings always fail the atomic check
with EINVAL. Putting the timings in the EDID itself is what makes them usable.

The plug's own base block and CTA extension are preserved, because they carry
the HDMI VSDB that declares the 600 MHz TMDS ceiling; dropping them would leave
the driver assuming HDMI 1.4 and rejecting anything above 340 MHz. Additional
CTA blocks carrying detailed timings are appended.

A DTD takes an arbitrary hactive, so unlike KWin's CVT custom modes these are
not rounded down to a multiple of 8: 1180x820 stays 1180x820.

Usage: python3 mk-sunshine-edid.py <source.bin> <output.bin>
"""

import sys

CELL_GRAN = 8
MIN_V_PORCH = 3
CLOCK_STEP_KHZ = 250
RB_H_BLANK = 160
RB_H_SYNC = 32
RB_H_FRONT = 48
RB_MIN_V_BLANK_US = 460.0
RB_V_FRONT = 3

# Physical size the plug already advertises, in mm.
H_SIZE_MM = 620
V_SIZE_MM = 340

# A DTD stores its pixel clock in 10 kHz units across 16 bits.
DTD_MAX_CLOCK_KHZ = 655350

# Exact Moonlight client resolutions. 3440x1440 above 100 Hz is deliberately
# absent: CVT-RB puts it at 659 MHz and up, past both the DTD field and the
# plug's 600 MHz TMDS ceiling.
MODES = [
    (3440, 1440, 60),
    (3440, 1440, 100),
    (2856, 1280, 60),  # Pixel 9 Pro
    (2360, 1640, 60),  # iPad
    (1428, 640, 60),  # Pixel 9 Pro, half
    (1240, 1080, 60),  # AYN Thor lower display
    (1180, 820, 60),  # iPad, half
]


def vsync_lines(width, height):
    ratio = width / height
    for target, lines in ((4 / 3, 4), (16 / 9, 5), (16 / 10, 6), (5 / 4, 7), (15 / 9, 7)):
        if abs(ratio - target) < 0.02:
            return lines
    return 10


def cvt_rb(width, height, refresh):
    """CVT 1.2 reduced-blanking v1 timings, in pixels and lines."""
    v_sync = vsync_lines(width, height)
    h_period_est = ((1000000.0 / refresh) - RB_MIN_V_BLANK_US) / height
    vbi_lines = int(RB_MIN_V_BLANK_US / h_period_est) + 1
    act_vbi = max(vbi_lines, RB_V_FRONT + v_sync + MIN_V_PORCH)

    total_v = act_vbi + height
    total_h = width + RB_H_BLANK
    clock_khz = int((refresh * total_v * total_h / 1000.0) / CLOCK_STEP_KHZ) * CLOCK_STEP_KHZ

    return {
        "width": width,
        "height": height,
        "clock_khz": clock_khz,
        "h_blank": RB_H_BLANK,
        "h_front": RB_H_FRONT,
        "h_sync": RB_H_SYNC,
        "v_blank": act_vbi,
        "v_front": RB_V_FRONT,
        "v_sync": v_sync,
        "refresh": clock_khz * 1000.0 / (total_h * total_v),
    }


def dtd(t):
    """Pack timings into an 18-byte detailed timing descriptor."""
    clock = t["clock_khz"] // 10
    if t["clock_khz"] > DTD_MAX_CLOCK_KHZ:
        raise ValueError("%.2f MHz exceeds the DTD pixel clock field" % (t["clock_khz"] / 1000.0))

    w, h = t["width"], t["height"]
    hb, vb = t["h_blank"], t["v_blank"]
    hf, hs = t["h_front"], t["h_sync"]
    vf, vs = t["v_front"], t["v_sync"]

    return bytes([
        clock & 0xFF, (clock >> 8) & 0xFF,
        w & 0xFF, hb & 0xFF, ((w >> 8) << 4) | (hb >> 8),
        h & 0xFF, vb & 0xFF, ((h >> 8) << 4) | (vb >> 8),
        hf & 0xFF, hs & 0xFF, ((vf & 0xF) << 4) | (vs & 0xF),
        ((hf >> 8) << 6) | ((hs >> 8) << 4) | ((vf >> 4) << 2) | (vs >> 4),
        H_SIZE_MM & 0xFF, V_SIZE_MM & 0xFF,
        ((H_SIZE_MM >> 8) << 4) | (V_SIZE_MM >> 8),
        0, 0,
        0x1A,  # digital separate sync, HSync positive, VSync negative
    ])


def cta_extension(dtds):
    """A CTA-861 rev 3 block carrying nothing but detailed timings."""
    if len(dtds) > 6:
        raise ValueError("a CTA block holds at most 6 DTDs")
    block = bytearray([0x02, 0x03, 0x04, 0x00])
    for d in dtds:
        block += d
    block += bytes(127 - len(block))
    block.append((-sum(block)) & 0xFF)
    return block


def main():
    src, dst = sys.argv[1], sys.argv[2]
    orig = bytearray(open(src, "rb").read())
    if len(orig) != 256:
        sys.exit("expected a 256-byte source EDID, got %d" % len(orig))

    base = bytearray(orig[0:128])

    # Rename the monitor so the overridden EDID is identifiable at a glance.
    for off in (0x36, 0x48, 0x5A, 0x6C):
        if base[off:off + 3] == b"\x00\x00\x00" and base[off + 3] == 0xFC:
            base[off + 5:off + 18] = (b"SUNSHINE\n" + b" " * 4)[:13]
            break

    packed = []
    for width, height, refresh in MODES:
        t = cvt_rb(width, height, refresh)
        packed.append(dtd(t))
        print("  %4dx%-4d @%3d -> %7.2f MHz, %.2f Hz"
              % (width, height, refresh, t["clock_khz"] / 1000.0, t["refresh"]))

    blocks = [bytearray(orig[128:256])]
    for i in range(0, len(packed), 6):
        blocks.append(cta_extension(packed[i:i + 6]))

    base[126] = len(blocks)
    base[127] = (-sum(base[0:127])) & 0xFF

    out = bytes(base) + b"".join(bytes(b) for b in blocks)
    for i in range(0, len(out), 128):
        if sum(out[i:i + 128]) % 256 != 0:
            sys.exit("block %d checksum is wrong" % (i // 128))

    open(dst, "wb").write(out)
    print("wrote %d bytes, %d extension blocks, %d added modes"
          % (len(out), len(blocks), len(packed)))


main()
