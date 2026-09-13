# USB sharing

The **USB Sharing** tray applet uses Linux USB/IP through an SSH reverse tunnel.
Select a local device/port, then **Send to** a recipient. **End sharing** releases
that port and restores the local driver. Each port can have one recipient;
different ports can go to different machines.

Recipients are `taylor-desktop-nix`, `taylor-cube-nix`, and `sunshine-nix`.
The current machine is omitted from its own menu. Sunshine is received by
`server-nix`, which hotplugs the imported device nodes into the Incus container.
The existing host udev-data mount provides input metadata there.

The applet is enabled with the shared Hyprland desktop configuration (the
desktop, the laptop, and the cube). The cube both exports and receives; its
user key is authorized on `taylor-desktop-nix` and `server-nix`. The reusable
Home Manager module also supports a regular graphical session, such as Plasma.

## Session behavior

- Selection follows the USB bus/port ID, including devices reconnected to that
  port. USB 2 and USB 3 connections on one physical socket can have different
  IDs; moving hubs also changes IDs.
- A separate systemd user service owns each selection. Closing/restarting the
  applet leaves sharing running. Logging out or rebooting ends selections.
- Connection failures and unplugging cause retries; status appears in the menu.
- Sharing removes the device from local applications. The confirmation applies
  to everything subsequently plugged into that selected port.
- Hubs and imported USB devices are excluded. Mounted storage and active swap
  are rejected; unmount storage before sharing. Do not mount it locally during
  connection retries. Unmount it on the recipient before ending sharing.
- Sunshine receives USB raw nodes and supported kernel-created device nodes
  (input, hidraw, audio, serial, video/media, and block devices). Network adapters
  cannot be transferred into the container by this mechanism. Container device
  discovery, application hotplug, and performance still need hardware testing.

## Configuration and activation

NixOS: `my.usbip.enable`, `exporter`, `receiver`, `users`, and
`containerRecipient`. Home Manager: `my.usbipTray.enable` and `recipients`.
Each recipient has an `ssh` address and optional `container = true`.

Deploy the source host, the cube for cube reception, and `server-nix` for
Sunshine reception. Desktop reception requires deploying the desktop. No
Sunshine guest rebuild is needed for this feature. Deployment requires approval
under this repository's rules; no deployment was performed while adding it.

SSH uses the user's existing credentials, strict host-key checks, and batch
mode. The desktop/laptop SSH keys and recipient host-key configuration already
exist in this repository. A new source needs its public key authorized on every
receiver. Authentication failures appear in the tray; it never prompts for a
password in the background.

Only the fixed, root-owned helper has passwordless sudo access for configured
users. It validates port IDs, limits receiver connections to loopback high ports,
and permits only the configured Incus container. This permission allows those
users to move USB devices between hosts. No secrets or new keys are created.
USB/IP's daemon is restricted to loopback by systemd IP address filtering and no
USB/IP firewall port is opened. SSH carries both control and USB traffic.

## Checks and troubleshooting

Hardware-free tests: `python3 pkgs/usbip-tray/test_usbip.py`.

```sh
systemctl --user status usbip-tray
systemctl --user list-units 'usbip-port-*'
journalctl --user -u 'usbip-port-*'
# Example manual end for a selected bus/port:
systemctl --user stop usbip-port-1-2.service
```

After deployment, test an expendable controller first: send it, check the
recipient, unplug/replug into the same port, then end sharing and check local
operation. Repeat for Sunshine and check both `/dev/input` and the game. Test
network interruption and simultaneous sessions before relying on them.

An unclean server shutdown can leave `usbip-tray-*` Incus device entries behind;
remove those stale entries using `incus config device remove sunshine-nix NAME`
on server-nix after checking that no sharing session owns them.

References: [Linux USB/IP](https://github.com/torvalds/linux/blob/master/tools/usb/usbip/README),
[Incus USB devices](https://linuxcontainers.org/incus/docs/main/reference/devices_usb/).
