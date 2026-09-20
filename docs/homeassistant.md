# Home Assistant

`homeassistant-nix` runs the NixOS Home Assistant service in an Incus LXC,
using the fleet's stable nixpkgs, shared LXC base, SSH access, and monitoring.
It is a manual-only Colmena target while HVAC control is being commissioned.
This is the NixOS-packaged installation, without Home Assistant OS/Supervisor
or its app management; additional services belong in NixOS modules.

Declared resources: 2 CPUs, 4 GiB memory, 16 GiB root on `rpool`, separate
`/nix` on `downloadHDD/nix-stores/homeassistant-nix`, bridged to `br0`.
The LAN reservation is `10.73.73.34`, MAC `02:5f:6e:64:81:22`;
Taylor has configured it in OPNsense.
After provisioning, open `http://homeassistant-nix.lan:8123` to onboard.

## Provisioning

Follow the existing `nixos-factory` workflow on build-nix, choosing `create`
and `homeassistant-nix`. The Incus reconciliation service does not create
missing containers. Before provisioning:

1. Review, commit, and push the configuration.
2. Reserve the declared IP/MAC in the active DHCP server. The NixOS DHCP
   module derives reservations from topology, but is currently disabled;
   adding topology alone does not configure the active DHCP server.
3. Deploy AdGuard's updated topology for DNS and build-nix's updated factory
   topology. Each deployment requires separate approval under AGENTS.md.
4. Run the factory workflow with approval for its provisioning and deployments.
   It reuses the instance declaration, provisions the separate store, registers
   SSH trust and the age recipient, and deploys build-nix and the new host.

The factory skips its DNS deployment when topology already contains the host,
which is why DNS must be applied beforehand. Subsequent service changes use
`deploy homeassistant-nix`, also after commit/push and deployment approval.

## Declarative configuration and persistent state

Edit `modules/software/services/homeassistant/default.nix` for packaged integrations,
base configuration, helpers, templates, scripts, and automations. Add declarative
automations to `services.home-assistant.config."automation manual"`. UI-created
automations, scripts, and scenes have separate writable includes, initialized
only when absent.

Pair integrations in the UI. Accounts, credentials, integration entries, entity
registries, dashboards, and history persist under `/var/lib/hass` on the root
disk. Back up this directory (including `.storage`) before relying on the system;
the Nix configuration alone cannot restore pairings. Never copy credentials or
the state directory into git. Recorder history retention is 14 days.

## FK-UFO-R6 and Daikin control

The FK-UFO-R6 is a FrankEver Wi-Fi IR remote with temperature/humidity sensors.
These units are already paired in Smart Life and successfully control the
Daikins. **Local-only operation is required**, with device internet access and
access to the trusted LAN blocked. Cloud scenes are not an acceptable fallback.
The official cloud Tuya integration is not included in this configuration.

Assigned device addresses (MACs remain managed in OPNsense):

| Device | Address |
| --- | --- |
| Office | `10.73.73.201` |
| Bedroom | `10.73.73.202` |
| Living room | `10.73.73.203` |

Create MAC-based reservations in OPNsense and add these addresses to the
existing blocked-device alias. These IPs fall within the repository's declared
DHCP pool (`.100`–`.245`); ensure the active DHCP configuration will not lease
them to other clients.

The packaged integration is `make-all/tuya-local`. Its `ir_remote_sensors`
profile covers this device class: a `remote` entity on dps 201 (send) and 202
(receive), plus temperature (dps 101) and humidity (dps 102) sensors. IR is
learned and replayed locally with `remote.learn_command` and
`remote.send_command`. Smart Life's virtual AC entries are separate cloud-only
sub-devices that tuya-local cannot add, so every Daikin command has to be
learned from the handheld remote instead of imported.

That profile matches on product ID only, and the FK-UFO-R6 matches it. The
office unit came up as `AC Controller Office` with exactly this entity set:

| Entity | Purpose |
| --- | --- |
| `remote.ac_controller_office` | learn/send IR |
| `infrared.ac_controller_office` | send-only IR |
| `sensor.ac_controller_office_temperature` | room temperature |
| `sensor.ac_controller_office_humidity` | room humidity |

No other config in tuya-local pairs a remote with both sensors, so the match is
unambiguous.

**Local IR learning does not work on this firmware.** The device accepts
`{"control":"study"}` on dps 201 and echoes it back, but never reports a
captured code: across repeated attempts dps 202 appeared zero times in the
debug log, and `remote.learn_command` times out every time. The Smart Life app
*can* learn the same buttons, so the receiver hardware is fine and the firmware
simply reports captures to the cloud only. Do not spend more time on it.

Sending is unaffected, and that is all this design needs.

Commission one unit first:

1. Identify its product ID, firmware version, and IP. Obtain its device ID and
   local key privately using Tuya Local's documented setup. Its cloud-assisted
   key retrieval is a one-time onboarding option, not a runtime dependency;
   manual setup is available when these details are already known. Do not
   reset/re-pair after retrieving the key, as pairing can change it. Never put
   keys in Nix, git, or diagnostics shared with an agent.
2. Add **Tuya Local** in Settings > Devices & services, starting with the office
   at `10.73.73.201`, and confirm it offers the universal-remote-with-sensors
   profile. The integration is installed through
   `pkgs.home-assistant-custom-components.tuya_local` (2026.5.2 in the current
   flake lock), so no HACS installation is needed.
3. Verify local sensor readings. IR commands come from the generated code
   table described below, not from learning.
4. Block WAN and power-cycle the blasters.

**All three passed on 2026-09-19.** With WAN blocked in OPNsense, sensors kept
reporting and control kept working; after a power cycle the units rejoined and
re-established their local sessions fast enough that tuya-local never marked
the entities unavailable. The stock firmware does not need the cloud to boot,
so replacing it buys nothing here and the FrankEver units can stay as they are.

Worth knowing for the next fault: tuya-local holds one local TCP session per
device for both reads and writes, so live sensor readings are evidence that
the control path works, not just the sensor path.

## Daikin IR codes

The handheld remote is an **ARC452A21**, driving FTXS\*\*LVJU heads. SmartIR
entry 1118 covers exactly that pair, in Broadlink base64. `tinytuya`'s
`IRRemoteControlDevice` converts between pulse timings and Tuya's base64, so
those captures become Tuya codes without any learning.

Decoding them yields the standard Daikin three-frame message. Only the third
frame carries state:

| Byte | Meaning |
| --- | --- |
| 0-2 | `11 da 27`, the Daikin signature |
| 5 | mode and power: `0x39` cool on, `0x49` heat on, low nibble `0` = off |
| 6 | target temperature in Celsius, doubled |
| 8 | fan: `0x30`-`0x70` for speeds 1-5, `0xa0` auto |
| 18 | checksum: sum of bytes 0-17, mod 256 |

Frame 1's byte 5 is the remote's own clock, not control data, which is why it
differs between captures taken minutes apart. Frame 0 is constant.

`generate-daikin-codes.py` patches those bits inside a verified capture rather
than synthesising pulse trains, so timing and framing stay exactly as recorded.
Run it against SmartIR 1118 with a Python that has `tinytuya`:

```
python3 generate-daikin-codes.py 1118.json --selftest   # 84 captures
python3 generate-daikin-codes.py 1118.json 64 86 > daikin-arc452a21.json
```

The selftest re-encodes every capture and compares bytes. Two upstream entries
are defective and will not match: `cool/4/20` is shifted a bit (its header
decodes as `23 b4 4f`) and `heat/2/22` sets a stray `0x80` in byte 10. All
generated codes therefore come from one clean template rather than per-mode
captures, which normalises both defects away.

**The table is keyed in Fahrenheit, deliberately.** SmartIR 1.18.1 has no
`temperatureUnit` field: it takes `hass.config.units.temperature_unit` and
publishes `minTemperature`/`maxTemperature` verbatim. Under `us_customary` a
Celsius-keyed table therefore shows up as "18-30 F". Setpoints are looked up
with `'{0:g}'.format(target)`, so the keys are plain strings like `"72"`.

Byte 6 is Celsius doubled, so the protocol carries half degrees natively.
Rounding each Fahrenheit step to the nearest half degree keeps one distinct
code per step instead of collapsing pairs onto the same setpoint.

The generated table spans 64-86 F (18-30 C), both modes and all six fan
settings: 277 codes. SmartIR 1118's own 20-26 C range was one contributor's
capture range, not a hardware limit.

Verified on hardware: `off`, `cool/auto/20`, `cool/auto/24`, `heat/auto/26`
and `heat/5/26` all produce the correct mode, setpoint and fan on the office
head. The generator reproduces the decoded bytes of all five exactly.

## Climate entities

SmartIR's `BroadlinkController` is not Broadlink-specific. With `Base64`
encoding it calls `remote.send_command` with a `b64:` prefix against whatever
entity `controller_data` names, and tuya-local's remote entity implements that
same convention. So SmartIR drives the blasters directly, with our code table
substituted for its own.

`default.nix` bakes `daikin-arc452a21.json` into the SmartIR package as device
code 9000. SmartIR resolves device files from inside its component directory,
which is a read-only store path here, and downloads from GitHub when one is
missing; baking it in avoids both. There is deliberately no top-level
`smartir:` section, because its `async_setup` returns early without one and
never registers the update check.

Each room's climate entity takes `temperature_sensor` from its own blaster, so
the thermostat reads room temperature rather than the head unit's return-air
sensor. That sensor placement is why the unit's own setpoints feel inaccurate:
it measures ceiling air, which is warmer than the occupied space, so it
overshoots in cooling and undershoots in heating.

## Network isolation

The blasters are in an OPNsense blocking alias with WAN denied, on the existing
LAN rather than an isolated IoT network. That blocks traffic traversing the
router but does not isolate them from peers on the same subnet.

The block must deny WAN only. Home Assistant on `10.73.73.34` still has to
reach `.201`-`.203` locally, and a rule broad enough to catch that looks
exactly like a firmware failure.

For full isolation, place the blasters on an isolated IoT VLAN/SSID. Deny WAN and new connections
to trusted LAN hosts, and isolate clients from each other. Allow Home Assistant
to initiate only the required local control connection to the reserved device
IPs, with stateful return traffic. Allow DHCP and any specifically required
local infrastructure services. Apply equivalent IPv6 policy or disable IPv6
on this segment. Use fixed addresses in the integration rather than depending
on broadcast discovery across VLANs.

Blocking all LAN traffic including Home Assistant would prevent Wi-Fi control.
Router rules also cannot isolate peers on the same layer-2 LAN by themselves;
the separate VLAN/SSID and AP isolation enforce that boundary. The IoT subnet,
device addresses, and router rules are not configured by this change.

## Control logic

`modules/software/services/homeassistant/hvac.nix` implements the room controller
and the YAML dashboard. The controller uses:

- Explicit heat/cool modes and setpoints, using measured room temperature.
- A deadband and command interval to prevent oscillation and IR flooding.
- Stale/unavailable sensor handling, startup reconciliation, and manual override.
- Full-state IR commands where supported, acknowledging that sent IR does not
  confirm the indoor unit received it.
- Coordination between heads sharing one outdoor unit before changing modes.

## Dashboard and overrides

The Rooms view uses responsive sections: three room panels on desktop and one
per row on a phone. Temperature and humidity are always measured room values;
the controller no longer rewrites the idle AC setpoint to make a dial look like
a room sensor. Each panel shows the active heating/cooling threshold, controller
status, and active timers. IR state is labelled as requested, not confirmed.

The Override panel has browser-local room tabs and pending temperature, on/off,
fan, and airflow controls. **Apply** copies that room's choices together and
starts its timer for the selected duration. **Resume schedule** cancels only
that room's override. Expiry restores normal temperature, power, fan, and airflow
behavior. “Normal setting” follows the standing fan/airflow preference.
System mode remains shared because all heads use the same outdoor unit.

Draft temperatures and power choices are seeded once from the active settings,
then restore the last selection across restarts. Background updates do not
overwrite pending edits. Fan and airflow drafts initially use “Normal setting”.
The Settings view holds seasonal mode and standing room fan/airflow preferences.

Bedroom nap has a duration selector and Start button. It uses the bedroom's
sleeping threshold for the current heating/cooling mode, quiet fan, and comfort
airflow, without changing other rooms or pending drafts. It replaces any bedroom
override and restores normal behavior when its timer ends. Starting a nap while
the system is off is disabled. **End bedroom override** ends the bedroom timer,
whether it was started by Nap or the Override panel.

The two compact controls are local custom Lovelace cards in `hvac-controls.js`,
bundled through Nix with a content-hashed filename. They load no external assets.

### Offline validation

With Python, Jinja2, and TinyTuya available:

```sh
node modules/software/services/homeassistant/test-hvac-controls.cjs
python3 modules/software/services/homeassistant/test-hvac.py
python3 modules/software/services/homeassistant/generate-daikin-codes.py \
  modules/software/services/homeassistant/daikin-arc452a21.json --validate-generated
```

The regression suite exercises template behavior and generated IR fields. It
does not contact Home Assistant or transmit IR. The generated-table validator
checks all 967 commands, including quiet fan, swing/comfort exclusivity, mode,
temperature, frame headers, and all frame checksums. Generation also validates
its output before writing JSON. `--selftest` remains for upstream Broadlink
source captures; `--validate-generated` is for the committed Tuya table.

These checks do not replace the deployment build, a browser check at desktop
and phone widths, or confirmation that the actual indoor units received IR.

References: [FrankEver FK-UFO-R6](https://frankever.com/fk-ufo-r6-smart-remote-control-with-humidity-and-temperature-sensor/),
[Tuya Local](https://github.com/make-all/tuya-local),
[local IR AC control](https://github.com/make-all/tuya-local/discussions/5449),
[Daikin integration](https://www.home-assistant.io/integrations/daikin/),
[splitting configuration](https://www.home-assistant.io/docs/configuration/splitting_configuration/).
