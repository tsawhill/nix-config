"""Small privileged USB/IP lease helper. All configuration is root-owned."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time

USB = Path('/sys/bus/usb/devices')
RUNTIME = Path('/run/usbip-tray')
RECORDS = Path('/run/vhci_hcd')
MATCH_BUSID = Path('/sys/bus/usb/drivers/usbip-host/match_busid')


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=25)


def busid(value):
    if not re.fullmatch(r'[1-9][0-9]*-[1-9][0-9]*(\.[1-9][0-9]*)*', value):
        raise ValueError('Invalid USB port')
    return value


def deviceid(value):
    # Incus compares these against udev's own lowercase, zero-padded properties.
    if not re.fullmatch(r'[0-9a-f]{4}', value):
        raise ValueError('Invalid USB device ID')
    return value


def eligible(path):
    if 'vhci_hcd' in str(path.resolve()):
        raise ValueError('Cannot re-export an imported device')
    if (path / 'bDeviceClass').read_text().strip() == '09':
        raise ValueError('USB hubs cannot be shared')
    # Mounted filesystems and active swap must remain on their current host.
    numbers = {p.read_text().strip() for p in path.resolve().rglob('dev')
               if '/block/' in str(p)}
    mounted = {line.split()[2] for line in Path('/proc/self/mountinfo').read_text().splitlines()}
    for line in Path('/proc/swaps').read_text().splitlines()[1:]:
        st = os.stat(line.split()[0])
        mounted.add(f'{os.major(st.st_rdev)}:{os.minor(st.st_rdev)}')
    if numbers & mounted:
        raise ValueError('Unmount this device and disable its swap before sharing')


def alive():
    """EOF from the owning process ends the lease, even after a crash."""
    ready, _, _ = select.select([sys.stdin], [], [], 1)
    return not ready or bool(os.read(sys.stdin.fileno(), 4096))


def lock(name):
    handle = (RUNTIME / name).open('w')
    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    return handle


def export(cfg, device):
    with lock('export-' + device):
        path = USB / device
        eligible(path)
        if (path / 'driver').resolve().name == 'usbip-host':
            raise ValueError('Device is already exported')
        try:
            run(cfg['usbip'], 'bind', '--busid=' + device)
            print('READY', flush=True)
            while alive() and path.exists():
                pass
        finally:
            if path.exists() and (path / 'driver').resolve().name == 'usbip-host':
                run(cfg['usbip'], 'unbind', '--busid=' + device)
            elif MATCH_BUSID.exists():
                # An unplug removes sysfs before unbind can remove the match.
                # Leaving this behind would capture the next device silently.
                MATCH_BUSID.write_text('del ' + device)


def ports():
    result = {}
    for status in Path('/sys/devices/platform/vhci_hcd.0').glob('status*'):
        for line in status.read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 7:
                result[int(fields[1])] = (int(fields[2]), fields[6])
    return result


def container_records(device):
    """Host udev record names for the input nodes of this imported USB."""
    found = []
    try:
        root = (USB / device).resolve(strict=True)
        entries = list(root.rglob('dev'))
    except OSError:
        return ()
    for entry in entries:
        try:
            uevent = entry.parent / 'uevent'
            if not uevent.exists():
                continue
            attrs = dict(line.split('=', 1) for line in uevent.read_text().splitlines() if '=' in line)
            if not attrs.get('DEVNAME', '').startswith(('input/', 'hidraw')):
                continue
            number = entry.read_text().strip()
        except OSError:
            # An unplug removes sysfs entries while this walk is in progress.
            continue
        if re.fullmatch(r'\d+:\d+', number):
            found.append('c' + number)
    return tuple(sorted(found))


def container_metadata(cfg, records):
    """Mirror the host's udev records so libinput can classify the devices."""
    if not records:
        return
    # The container's udevd answers each injected event with an empty record.
    script = ('/run/current-system/sw/bin/mkdir -p /run/udev/data\n'
              'for record in "$@"; do\n'
              '  /run/current-system/sw/bin/ln -sfnT "/opt/host-udev-data/$record" '
              '"/run/udev/data/$record"\n'
              'done')
    run(cfg['incus'], 'exec', cfg['container'], '--',
        '/run/current-system/sw/bin/sh', '-c', script, 'sh', *records)


def receive(cfg, device, tcp_port, container, vendor=None, product=None):
    if container and not cfg.get('container'):
        raise ValueError('This host is not a container receiver')
    if not 20000 <= tcp_port <= 60000:
        raise ValueError('Invalid tunnel port')
    port = None
    hotplug = None
    imported = ''
    records = ()
    settle = 0
    # A per-tunnel lock prevents another lease from cleaning up its devices.
    with lock('receive-' + str(tcp_port)):
        try:
            if container:
                # Incus injects udev events only for devices that appear after
                # this watch exists, and libinput needs them to see the import.
                hotplug = 'usbip-tray-' + str(tcp_port)
                run(cfg['incus'], 'config', 'device', 'add', cfg['container'], hotplug,
                    'unix-hotplug', 'vendorid=' + vendor, 'productid=' + product,
                    'mode=0660', 'uid=1000', 'gid=174', 'required=false')
            # Serialize allocation and identify the port from usbip's own record.
            with (RUNTIME / 'attach.lock').open('w') as allocation:
                fcntl.flock(allocation, fcntl.LOCK_EX)
                before = ports()
                try:
                    run(cfg['usbip'], '--tcp-port=' + str(tcp_port), 'attach',
                        '--remote=127.0.0.1', '--busid=' + device)
                finally:
                    for candidate, (state, _) in ports().items():
                        record = RECORDS / ('port' + str(candidate))
                        if state != 4 and before.get(candidate, (4, ''))[0] == 4:
                            if record.exists() and record.read_text().split() == ['127.0.0.1', str(tcp_port), device]:
                                port = candidate
                if port is None:
                    raise RuntimeError('Could not identify the imported USB port')
            deadline = time.monotonic() + 15
            while alive():
                state, local = ports().get(port, (4, ''))
                if state in (4, 7):
                    break
                if state == 6 and (USB / local).exists():
                    imported = local
                    if container:
                        found = container_records(local)
                        if found != records:
                            records, settle = found, 10
                        if settle:
                            settle -= 1
                            container_metadata(cfg, records)
                    if deadline:
                        print('READY', flush=True)
                        deadline = 0
                elif deadline and time.monotonic() > deadline:
                    raise RuntimeError('USB device did not enumerate')
        finally:
            # Detach first, so the removal events reach the container.
            if port is not None:
                run(cfg['usbip'], 'detach', '--port=' + str(port), check=False)
            if hotplug:
                grace = time.monotonic() + 5
                while imported and (USB / imported).exists() and time.monotonic() < grace:
                    time.sleep(0.1)
                time.sleep(1)
                try:
                    run(cfg['incus'], 'config', 'device', 'remove', cfg['container'], hotplug)
                except Exception as error:
                    raise RuntimeError('Container cleanup failed: ' + str(error))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['export', 'receive', 'receive-container'])
    parser.add_argument('device', type=busid)
    parser.add_argument('port', type=int, nargs='?')
    parser.add_argument('vendor', type=deviceid, nargs='?')
    parser.add_argument('product', type=deviceid, nargs='?')
    args = parser.parse_args(sys.argv[2:])
    cfg = json.loads(Path(sys.argv[1]).read_text())
    if os.geteuid() != 0:
        raise ValueError('This helper must run through sudo')
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    if args.action == 'export' and cfg['exporter']:
        export(cfg, args.device)
    elif args.action.startswith('receive') and cfg['receiver'] and args.port is not None:
        container = args.action == 'receive-container'
        if container and not (args.vendor and args.product):
            raise ValueError('Container receivers need the device IDs')
        receive(cfg, args.device, args.port, container, args.vendor, args.product)
    else:
        raise ValueError('Action not enabled on this host')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        detail = getattr(error, 'stderr', None) or str(error)
        print(detail, file=sys.stderr)
        sys.exit(1)
