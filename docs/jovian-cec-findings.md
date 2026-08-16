# HDMI-CEC on the Valve Steam Machine (Fremont) under Jovian-NixOS

Working notes behind two proposed Jovian-NixOS changes. Verified on
`taylor-cube-nix`, a retail Steam Machine, 2026-08-16.

## Hardware / versions

| | |
|---|---|
| DMI | `sys_vendor=Valve`, `product_name=Fremont`, `board_name=Fremont` |
| BIOS | `F7F0105`, 2026-02-26 |
| GPU | amdgpu `0000:03:00.0`, HDMI-A-1 connected, DP-1 disconnected |
| EC | ITE `it81302`, exposed as `cros-ec-*` platform devices (`GOOG0004:00`) |
| Kernel | `linux-jovian` 6.18.42-valve2 |

CEC hardware is a CEC controller behind the ChromeOS-style EC, driven by
`drivers/media/cec/platform/cros-ec/cros-ec-cec.c` (`CONFIG_CEC_CROS_EC`).

## Symptom

`jovian.steamos.enableHdmiCecIntegration = true` produces a fully populated
CEC menu in Game Mode that does nothing. `cecd` runs and owns
`com.steampowered.CecDaemon1`, so Steam draws the UI whether or not any
adapter exists.

## Finding 1 — the CEC drivers are never built

`drivers/media/cec/Kconfig` gates every adapter driver behind
`MEDIA_CEC_SUPPORT`:

```
menuconfig MEDIA_CEC_SUPPORT
	bool
	prompt "HDMI CEC drivers"
	default y if MEDIA_SUPPORT && !MEDIA_SUPPORT_FILTER
if MEDIA_CEC_SUPPORT
source "drivers/media/cec/i2c/Kconfig"
source "drivers/media/cec/platform/Kconfig"
source "drivers/media/cec/usb/Kconfig"
endif
```

`linux-jovian` does not set it, so `drivers/media/cec/` ships only `core`:

```
# CONFIG_MEDIA_CEC_SUPPORT is not set
$ ls .../kernel/drivers/media/cec/
core
```

The platform device enumerates but binds nothing:

```
$ ls /sys/bus/platform/devices/cros-ec-cec.2.auto/
driver_override  modalias  power  subsystem  uevent      # no driver symlink
$ cat .../modalias
platform:cros-ec-cec
```

Valve's own shipping config **does** set these. From
`linux-neptune-618-headers-6.18.42.valve2-1-x86_64.pkg.tar.zst`
(`jupiter-main`), `usr/lib/modules/*/build/.config`:

```
CONFIG_MEDIA_CEC_SUPPORT=y
CONFIG_CEC_CROS_EC=m
CONFIG_USB_PULSE8_CEC=m
```

Note `USB_PULSE8_CEC` / `USB_RAINSHADOW_CEC` matter to Jovian independently:
`modules/steamos/cec.nix` already installs `inputattach-cec-units`, whose udev
rules match Pulse-Eight (`2548:1001/1002`) and RainShadow (`04d8:ff59`) and
start `inputattach@` units. Without those drivers built, that package is inert
on every Jovian system.

**Proposed fix** — in `pkgs/linux-jovian/default.nix` `structuredExtraConfig`:

```nix
MEDIA_CEC_SUPPORT = yes;
CEC_CROS_EC = module;
USB_PULSE8_CEC = module;
USB_RAINSHADOW_CEC = module;
```

Cost is near zero elsewhere: `MEDIA_CEC_SUPPORT` is a menuconfig bool that adds
no code by itself, and `cros-ec-cec` refuses to probe on hardware absent from
its DMI table.

## Finding 2 — a load-order race leaves the adapter with no physical address

With the drivers built, `/dev/cec0` appears and `cecd` adopts it, but:

```
Driver Name          : cros-ec-cec
OSD Name             : 'Steam Machine'      # cecd configured it
Connector Info       : None
Physical Address     : f.f.f.f
Logical Address Mask : 0x0000
$ cat /sys/class/chromeos/cros_ec/cec_phys_addr
0 65535
```

No physical address means no logical address and no bus traffic.

### Root cause

`cec_notifier_get_conn()` in `drivers/media/cec/core/cec-notifier.c` matches
asymmetrically:

```c
if (n->hdmi_dev == hdmi_dev &&
    (!port_name ||
     (n->port_name && !strcmp(n->port_name, port_name)))) {
```

A `NULL` lookup matches **any** notifier for the device. A named lookup matches
**only** an existing identical name. The two participants disagree:

- `cros-ec-cec` looks up by name — Fremont's DMI entry is
  `{ "Valve", "Fremont", "0000:03:00.0", port_c_conns }`, i.e. `"Port C"`
- `amdgpu` registers unnamed — `amdgpu_dm_initialize_hdmi_connector()` calls
  `cec_notifier_conn_register(hdmi_dev, NULL, &conn_info)`

So registration order decides the outcome:

| First | Result |
|---|---|
| `cros_ec_cec` | creates `"Port C"`; amdgpu's `NULL` wildcards onto it — **works** |
| `amdgpu` | creates unnamed; cros-ec-cec's `"Port C"` cannot match — **orphan** |

`CEC_CROS_EC` is a module loaded from udev, while `jovian.hardware.has.amd.gpu`
enables early modesetting and puts amdgpu in the initrd. amdgpu wins, and the
adapter ends up on an orphaned notifier that never receives EDID events.

This is **not** a source bug, and the `"Port C"` entry is not wrong: SteamOS
3.8.1x ships `linux-neptune-618-6.18.33.valve2`, whose `cros-ec-cec.c` DMI table
and `amdgpu_dm.c` registration are byte-identical, and CEC works there.
Jovian's 6.18.42-valve2 tag resolves to `af6356cf24889d27925360ea558a46993a629412`,
matching Valve's `...-neptune-618-gaf6356cf2488`.

### Verification

Re-registering amdgpu's notifier after `cros_ec_cec` is up fixes it, via the
per-connector debugfs toggle:

```
# echo 0 > /sys/kernel/debug/dri/0000:03:00.0/HDMI-A-1/hdmi_cec_state
# echo 1 > /sys/kernel/debug/dri/0000:03:00.0/HDMI-A-1/hdmi_cec_state
```

```
before: cec_phys_addr = 0 65535 ; Connector Info: None ; f.f.f.f
after:  cec_phys_addr = 0 12288 ; card 0, connector 121 ; 3.0.0.0 ; LA mask 0x0010
```

CEC then works end to end in Game Mode: TV control, remote passthrough, and
wake/suspend of the TV.

### Proposed fix

The debugfs toggle is a workaround, not a fix. Better candidates, in order of
preference:

1. Force the order with a modprobe softdep, e.g.
   `softdep amdgpu pre: cros_ec_cec` — **untested**, and needs checking that
   initrd modprobe honours it when amdgpu is loaded for early KMS.
2. Load `cros_ec_cec` (with its `cros_ec_lpcs` / `cros_ec_dev` dependencies) from
   the initrd ahead of amdgpu.
3. Upstream: make the notifier lookup order-independent, or have `cros-ec-cec`
   fall back to an unnamed lookup when the named one finds nothing. This is the
   real bug and affects any system pairing early-KMS amdgpu with a cros-ec CEC
   adapter.

A local stopgap using the debugfs toggle lives in
`hosts/taylor-cube-nix/system/hardware/cec.nix`. Note it must wait on
`/dev/cec0`, not on `cec_phys_addr`: the EC retains that value across a warm
reboot, so it reads stale-valid and skips the work. `cros_ec_cec_init_port()`
registers the notifier before `cec_register_adapter()`, so the node's existence
is the correct signal.

## Unrelated: LED brightness

Steam's LED brightness slider writes `brightness_scale`, a global EC register
that has no effect here — the driver sets it to 0 at probe (BIOS startup
brightness) while the LEDs stay at full. Per-LED `brightness` does work, since
`valve_leds_set_brightness()` runs `led_mc_calc_color_components()` and writes
the RGB registers. Mirroring one onto the other makes the slider work, including
under animated effects. See `hosts/taylor-cube-nix/system/hardware/leds.nix`.

Also note `valve-leds` sysfs attributes are root-owned `0644`, so the gamescope
session cannot write them at all without a udev rule loosening them — comparable
to `jovian.hardware.amd.gpu.enableBacklightControl`.
