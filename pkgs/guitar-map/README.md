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
Enter accepts the mapping. The snippet is printed and optionally saved to a new
file (existing files are never overwritten). Put it in
`modules/software/guitars/<device-mode>.nix` to auto-import it on gaming hosts,
or import it into a single host config. The output contains an SDL mapping in
a gated Nix module; it does not generate udev rules, Steam exclusions, DLL
configuration, or firmware settings.
After applying the configuration, log out and back in to refresh session env.
No config is applied by the wizard itself.

## Profile layout

`modules/software/guitars/default.nix` imports every sibling `.nix` profile,
exports the merged SDL mappings, and combines optional Steam device exclusions.
`gaming.nix` imports this directory. `minihost.nix` owns the existing adapter's
mapping, Steam exclusion, and hidraw access rule. New profiles can carry their
own device-specific rules when needed; these are not inferred from capture.

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
  with the same GUID use the same mapping. New mappings are appended after the
  MiniHost baseline, allowing a newly recorded mapping for that GUID to win.
  `lib.mkForce [ ... ]` can replace all mappings including the baseline.
- Steam Input, Wine's raw HID backend, and game-local DLLs can bypass or override
  SDL mappings. Test with Steam Input disabled for the game where appropriate.
  The custom `xinput-guitar-dll.c` still hardcodes buttons and clears several axes;
  it must not be expected to pass these new controls through. This tool does not
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
