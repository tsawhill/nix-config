# guitar-map

The gaming bundle installs `guitar-map`. Run it from a terminal on the machine
with the guitar connected:

```sh
guitar-map --output ./my-guitar.nix
```

Select the SDL joystick/USB receiver and press a control on it to confirm the
physical guitar (useful for identical devices), then follow the prompts for each fret,
strum direction, Start/Select, whammy, tilt, and standard controller extras.
Press `s` for absent inputs. Release everything before each capture, press Enter,
exercise only the requested control through its full travel, and press Enter
again. If several raw inputs change, choose the intended one or retry.

The final preview shows SDL's actual mapped values and raw inputs, including
unmapped axes/buttons. Scroll with arrow keys; `e` lets you re-record any input.
Enter accepts the mapping. The profile is printed and optionally saved to a new
file (existing files are never overwritten). Put it in
`modules/software/guitars/<slug>.nix` — the name the wizard suggests — to
auto-import it on gaming hosts, or import it into a single host config. The
output is a complete `guitarProfiles` entry: SDL mapping, USB IDs (which drive
the hidraw rule and Steam exclusion), and the measured DirectInput layout. It
is nixfmt-clean as printed. It does not change firmware, and no DLL reads the
DirectInput half yet.
After applying the configuration, log out and back in to refresh session env.
No config is applied by the wizard itself.

## DirectInput measurement

Each capture records the control twice: as an SDL binding, and as the
DIJOYSTATE2 member Wine's DirectInput exposes it on. When the device has a real
HID descriptor the two need not agree — SDL numbers buttons by evdev `BTN_*`
code, while DirectInput fills `rgbButtons` in HID declaration order — so that
case is measured rather than assumed.

The wizard reads the guitar's `hidraw` node and parses its HID report
descriptor, because Wine's hidraw backend passes that descriptor through to
`dinput` unchanged. The capture and preview screens show the live DirectInput
view alongside the SDL one, and the emitted profile records each measured
control's `rgbButtons`/`rgdwPOV` index or axis member, with each axis's logical
range — a whammy is not always the 0..65535 the shim used to assume.

That needs read access to `/dev/hidraw*`, which the profile's own `usb` block
grants: save the profile, rebuild, replug the guitar, then re-run the wizard to
measure it. Until then the wizard writes an empty `dinput` with the reason as a
comment.

**Devices with no hidraw node at all** are derived instead, with no second pass
and nothing to measure. An XInput-mode controller is the common case: its USB
interface is vendor-specific rather than HID, so `xpad` claims it and no HID
descriptor exists — not for guitar-map to read and not for Wine either. Wine
then synthesises a descriptor from what SDL reports, passing joystick indices
through in order, so SDL index N lands on DirectInput index N and axes fill
X/Y/Z/Rx/Ry/Rz in the same order. Ranges come out as dinput's own 0..65535
default rather than SDL's signed range. The wizard applies that mapping to the
bindings it just recorded and emits a complete `dinput`, labelled derived
rather than measured.

A derived layout rests on Wine's synthesis behaving that way; a traced launch
(`GUITAR_SHIM_TRACE=1`) is the way to check when a control misbehaves. The
shim's log also names the device it bound and its button/axis/POV counts, which
is how to tell a passed-through descriptor from a synthesised one.

## How a profile reaches the game

`guitarShimConfig` renders every profile that has USB IDs and a measured layout
into one line per guitar, and the Guitar Hero launchers export it as
`GUITAR_SHIM_CONFIG`:

```
1209:2882 a=b0 b=b1 back=b6 leftshoulder=b4 start=b7,b11 x=b2 y=b3 dpdown=p0 dpup=p0 rightx=lX:0:65535
```

`xinput-guitar-dll.c` parses that, matches a device by the VID/PID in its
DirectInput `guidProduct`, and applies that guitar's table. The DLL itself is
one fixed build shared by GH3 and GHWTDE — only the config varies, so adding a
guitar never rebuilds it.

`guitarShim.enable` on a game entry does the whole job: it overrides Wine's
`xinput1_3`, exports the config, and refreshes `xinput1_3.dll` beside the
executable on each launch. Wine only loads a native DLL from the game
directory, so a copy has to live there; installing it per launch keeps it in
step with the store rather than going stale. It is skipped when the file
already matches, so a library on Syncthing is not rewritten every launch, and a
read-only library mount warns instead of blocking the game. The DLL is also in
`environment.systemPackages`, with `xinput-guitar-dll-path` printing its store
path for a manual copy elsewhere.

The `dinput` keys name the XInput control the shim drives, not the SDL binding:
`rightx` is the whammy even on a guitar whose SDL line puts it on `leftx`.
Multiple indices are allowed (`start=b7,b11`) for controls that sit on more
than one physical button.

Every launch logs each enumerated device to `C:\gh-xinput-guitar.log` in the
game's prefix with its name, VID/PID and button/axis/POV counts, then whether it
matched a profile. `GUITAR_SHIM_TRACE=1` additionally logs every input change,
which is how to read a layout off a guitar from the Wine side. A guitar with no
matching profile is skipped and named in the log rather than being bound to some
other guitar's table. With no `GUITAR_SHIM_CONFIG` at all the DLL falls back to
the MiniHost layout it used to hardcode.

## Profile layout

`modules/software/guitars/default.nix` imports every sibling `.nix` profile and
defines `software.apps.gaming.guitarProfiles`. Each entry is one guitar and the
single source for everything derived from it: the merged SDL mappings file, the
`hidraw` uaccess rule, the Steam client exclusion, and the DirectInput layout.
`gaming.nix` imports this directory. A profile with `usb = null` contributes
only its SDL mapping. Host modules can still append to
`sdlGameControllerMappings` directly for one-off mappings that are not a
device profile.

Use one file per device/mode with a distinct mapping, for example
`crkd-les-paul-pc.nix`. A controller's mode/transport and SDL GUID matter more
than the product name. Avoid conflicting profiles for the same GUID; update
the existing profile when replacing a recording. Add new files to Git before
building the Git-backed flake so Nix includes them.

## USB ports and multiple guitars

Moving a guitar to another USB port does not require another profile: SDL's
GUID is intended to remain stable across ports and reboots. The MiniHost
hidraw rule and Steam exclusion also match vendor/product IDs, not USB paths.

Identical guitars in the same mode share one mapping and remain separate
controllers with independent button/axis state. Record one profile per GUID,
not one per physical guitar. The selection screen shows device paths, then
shows the serial (when provided) and requires physical input to confirm the
selected guitar. Paths, serials and connection IDs are not exported into the
mapping. The wizard tracks the selected connection by instance ID so an
unrelated unplug cannot make it preview a different guitar. Reconnecting the
selected guitar during capture requires restarting the wizard.

SDL mappings do not fix Player 1/2 order; use the game's controller assignment
or join flow. Two units sharing a GUID cannot receive different mappings via
this format. Different firmware/modes/transports can yield different GUIDs.
An adapter exposing multiple guitars as a single joystick also cannot be
split into multiple players by a mapping string.

The old custom XInput DLL is an additional limitation: it selects the first
DirectInput controller and rejects every XInput index except zero. Multiple
guitars require a game/input backend or replacement DLL that supports multiple
controllers; the SDL profile cannot fix that DLL. BetterGH3's replacement still
needs an actual multiplayer test.

Reference: [SDL GUID identity documentation](https://wiki.libsdl.org/SDL2/SDL_GUID).

## Conventions and limitations

- Frets map to A/B/Y/X/LB, strum to D-pad up/down, whammy to right stick X,
  and tilt to right stick Y. These are configurable SDL assignments, not a
  promise that every game's guitar mode uses those axes. The older MiniHost
  baseline uses left X for whammy; verify the game with its chosen DLL.
- Extra standard inputs are prompted separately: RB, Guide, stick clicks,
  triggers, left stick axes, D-pad left/right, Share, paddles and touchpad click.
  SDL extras beyond standard XInput may only work in native SDL games.
- SDL gives each output control one input binding. If strum and D-pad up are
  separate physical buttons, or frets and face buttons are separate, choose
  which to use. Combining distinct sources into one output requires a remapper
  beyond SDL's mapping format. A physical right stick competes with whammy/tilt
  for the right stick outputs.
- Full axes resting at an endpoint are captured with inversion where needed;
  centered tilt/trigger inputs use a half axis. Left stick prompts request the
  positive direction (right/down). The wizard does not calibrate arbitrary
  axis endpoints or dead zones. Use `--threshold 6000` for small movements;
  check neutral and extremes in the live display.
- This works with SDL-visible devices, wired or wireless, without a MiniHost
  dependency. It cannot expose controls hidden by firmware, a device's selected
  mode, missing drivers, or sensors not presented as joystick axes. Changing
  firmware modes or USB/Bluetooth transport may require a separate mapping.
- Mappings identify the device's SDL GUID, not its serial number. Two devices
  with the same GUID use the same mapping. Profiles are keyed by name rather
  than ordered, so re-recording a guitar means replacing that profile's `sdl`
  line; two profiles carrying the same GUID leave which one wins undefined.
- Steam Input, Wine's raw HID backend, and game-local DLLs can bypass or override
  SDL mappings. Test with Steam Input disabled for the game where appropriate.
  `xinput-guitar-dll.c` passes through only the controls a profile's `dinput`
  block names; anything unmapped stays at rest. This tool does not
  modify/install/delete that DLL. Testing BetterGH3's bundled fix remains a
  separate game-folder step; preserve `WINEDLLOVERRIDES=xinput1_3=n,b` for a
  native DLL. A mapping by itself does not set XInput's guitar subtype.

## Checks

```sh
python3 -m unittest discover -s pkgs/guitar-map -v
```

Set `GUITAR_MAP_SDL_LIBRARY` to the SDL2 shared library path to include the
virtual joystick integration test. This checks actual SDL mapping, extra
buttons, whammy inversion, tilt, triggers, and replacing a mapping without
physical hardware. Physical capture and game compatibility still require a
connected guitar.
