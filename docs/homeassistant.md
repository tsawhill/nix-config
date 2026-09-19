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

Edit `modules/software/services/homeassistant.nix` for packaged integrations,
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

That profile matches on product ID only. As of tuya-local 2026.5.2 it lists
`whs3cty93fzrqkpt`, `jbe3snv4tki8oo9c` (S09), and `b1codgjxh0wf7qrf`; whether
the FK-UFO-R6 reports one of these is still unverified. If it does not, report
the product ID upstream rather than forcing an unrelated profile.

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
3. Verify local sensor readings, then learn Daikin commands with
   `remote.learn_command`. Minisplit remotes send full state in one frame, so
   learn one command per mode/setpoint/fan combination that the control logic
   will actually use. Record entity IDs, command names, units, and cadence.
4. Block WAN, power-cycle the blaster, and restart Home Assistant. Verify
   temperature updates and actual AC response still work without Smart Life
   running. Include an extended offline test for stock-firmware behavior.

If the stock firmware cannot meet this test, investigate replacement firmware
against the actual board/module and sensor wiring. Do not assume the model
name alone proves ESPHome/OpenBeken compatibility or flash a guessed pin map.

## Network isolation

The current deployment uses the existing LAN and an OPNsense blocking alias;
no isolated IoT network is currently planned. This blocks traffic traversing
the router, but does not isolate devices from peers on the same subnet.

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

Once temperature readings and a working command path are available, implement
room control declaratively with:

- Explicit heat/cool modes and setpoints, using measured room temperature.
- A deadband and command interval to prevent oscillation and IR flooding.
- Stale/unavailable sensor handling, startup reconciliation, and manual override.
- Full-state IR commands where supported, acknowledging that sent IR does not
  confirm the indoor unit received it.
- Coordination between heads sharing one outdoor unit before changing modes.

No live HVAC automation is enabled until the entities and behavior are verified.

References: [FrankEver FK-UFO-R6](https://frankever.com/fk-ufo-r6-smart-remote-control-with-humidity-and-temperature-sensor/),
[Tuya Local](https://github.com/make-all/tuya-local),
[local IR AC control](https://github.com/make-all/tuya-local/discussions/5449),
[Daikin integration](https://www.home-assistant.io/integrations/daikin/),
[splitting configuration](https://www.home-assistant.io/docs/configuration/splitting_configuration/).
