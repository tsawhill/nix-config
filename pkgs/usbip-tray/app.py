#!/usr/bin/env python3
"""GTK tray and independent per-port session supervisor for USB/IP over SSH."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import random
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import threading
import time

USB = Path('/sys/bus/usb/devices')
HELPER = '/run/current-system/sw/bin/usbip-tray-helper'
SUDO = '/run/wrappers/bin/sudo'


def export_command(bus):
    # sudoers authorizes the immutable store path, not the system-profile alias.
    return [SUDO, '-n', str(Path(HELPER).resolve(strict=True)), 'export', bus]


def receive_command(action, bus, tcp, vendor, product):
    # Resolve on the recipient: its helper has a different store path/config.
    resolve = shlex.join(['/run/current-system/sw/bin/readlink', '-e', HELPER])
    return (shlex.join([SUDO, '-n']) + ' "$(' + resolve + ')" '
            + shlex.join([action, bus, str(tcp), vendor, product]))


def usb_ids(bus):
    # The recipient cannot read these: an imported device loses its USB
    # ancestry, so only this host can tell Incus what to watch for.
    path = USB / bus
    return ((path / 'idVendor').read_text().strip(),
            (path / 'idProduct').read_text().strip())


def runtime():
    path = Path(os.environ['XDG_RUNTIME_DIR']) / 'usbip-tray'
    path.mkdir(mode=0o700, exist_ok=True)
    return path


def unit(bus):
    if not re.fullmatch(r'[1-9][0-9]*-[1-9][0-9]*(\.[1-9][0-9]*)*', bus):
        raise ValueError('Invalid USB port')
    return 'usbip-port-' + bus + '.service'


def devices():
    result = {}
    for path in USB.iterdir():
        if not re.fullmatch(r'\d+-\d+(\.\d+)*', path.name):
            continue
        try:
            if (path / 'bDeviceClass').read_text().strip() == '09' or 'vhci_hcd' in str(path.resolve()):
                continue
            product = (path / 'product').read_text().strip() if (path / 'product').exists() else 'USB device'
            result[path.name] = product
        except OSError:
            pass
    return result


def ready(process, log, timeout=35):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        readable, _, _ = select.select([process.stdout], [], [], 0.2)
        if readable:
            line = process.stdout.readline()
            if line.strip() == b'READY':
                return
            if not line:
                break
        if process.poll() is not None:
            break
    log.seek(0)
    raise RuntimeError(log.read().decode(errors='replace')[-1200:].strip() or 'Connection timed out')


def close(process):
    if process is None:
        return
    if process.stdin:
        process.stdin.close()
    try:
        process.wait(timeout=35)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def session(cfg, bus, target):
    destination = cfg['recipients'][target]
    statefile = runtime() / (bus + '.json')
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())

    def status(message):
        value = {'target': target, 'status': message}
        tmp = statefile.with_suffix('.tmp')
        tmp.write_text(json.dumps(value))
        tmp.replace(statefile)

    try:
        while not stopping.is_set():
            exporter = receiver = None
            with tempfile.TemporaryFile() as log:
                phase = 'USB session'
                try:
                    if not (USB / bus).exists():
                        status('Waiting for a device in this port')
                        stopping.wait(2)
                        continue
                    phase = 'Local USB export'
                    status('Connecting…')
                    identity = usb_ids(bus)
                    exporter = subprocess.Popen(export_command(bus),
                                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                    ready(exporter, log)
                    tcp = random.randint(20000, 60000)
                    action = 'receive-container' if destination.get('container', False) else 'receive'
                    phase = 'Receiver ' + target
                    receiver = subprocess.Popen([
                        cfg['ssh'], '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                        '-o', 'ConnectTimeout=8', '-o', 'ServerAliveInterval=5',
                        '-o', 'ServerAliveCountMax=3', '-o', 'ExitOnForwardFailure=yes',
                        '-o', 'ControlMaster=no', '-o', 'ControlPath=none',
                        '-R', f'127.0.0.1:{tcp}:127.0.0.1:3240',
                        destination['ssh'], receive_command(action, bus, tcp, *identity)],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                    ready(receiver, log)
                    status('Connected')
                    while not stopping.wait(1):
                        if exporter.poll() is not None or receiver.poll() is not None:
                            raise RuntimeError('Connection ended; retrying')
                except Exception as error:
                    status(phase + ': ' + str(error))
                finally:
                    close(receiver)
                    close(exporter)
            stopping.wait(4)
    finally:
        statefile.unlink(missing_ok=True)


def tray(cfg, config_path):
    import gi
    gi.require_version('Gtk', '3.0')
    gi.require_version('AyatanaAppIndicator3', '0.1')
    from gi.repository import Gtk, GLib, AyatanaAppIndicator3 as Indicator

    class Tray:
        def __init__(self):
            self.error = None
            self.snapshot = None
            self.indicator = Indicator.Indicator.new('usbip-tray',
                                                     str(Path(__file__).resolve().parent.parent / 'share/usbip-tray/icons/usb.png'),
                                                     Indicator.IndicatorCategory.HARDWARE)
            self.indicator.set_status(Indicator.IndicatorStatus.ACTIVE)
            self.refresh()
            GLib.timeout_add_seconds(2, self.refresh)

        def command(self, args):
            def worker():
                try:
                    subprocess.run(args, check=True, capture_output=True, text=True, timeout=100)
                except Exception as error:
                    self.error = getattr(error, 'stderr', None) or str(error)
                GLib.idle_add(self.refresh)
            threading.Thread(target=worker, daemon=True).start()

        def start(self, bus, target):
            dialog = Gtk.MessageDialog(message_type=Gtk.MessageType.QUESTION,
                                       buttons=Gtk.ButtonsType.OK_CANCEL,
                                       text=f'Share USB port {bus} with {target}?')
            dialog.format_secondary_text('The device will stop working locally. Anything reconnected to this port '
                                         'will also be shared until you choose End sharing. Unmount storage first.')
            answer = dialog.run()
            dialog.destroy()
            if answer != Gtk.ResponseType.OK:
                return
            self.command([cfg['systemdRun'], '--user', '--collect', '--unit=' + unit(bus),
                          '--property=PartOf=graphical-session.target',
                          '--property=KillMode=mixed', '--property=TimeoutStopSec=180',
                          sys.argv[0], '--config', str(config_path), 'session', bus, target])

        def refresh(self):
            states = {}
            for path in runtime().glob('*.json'):
                try:
                    states[path.stem] = json.loads(path.read_text())
                except (OSError, ValueError):
                    pass
            found = devices()
            snapshot = (found, states, self.error)
            if snapshot == self.snapshot:
                return True
            self.snapshot = snapshot
            menu = Gtk.Menu()

            def item(parent, label, callback=None):
                widget = Gtk.MenuItem(label=label)
                widget.set_sensitive(callback is not None)
                if callback:
                    widget.connect('activate', lambda _: callback())
                parent.append(widget)
                return widget

            item(menu, f'USB sharing · {len(states)} selected port(s)')
            if self.error:
                item(menu, self.error[:200])
                item(menu, 'Dismiss error', self.dismiss)
            for bus in sorted(found.keys() | states.keys()):
                state = states.get(bus)
                label = f'{bus} · {found.get(bus, "Device unplugged")}'
                if state:
                    label += ' → ' + state['target']
                parent = item(menu, label, lambda: None)
                submenu = Gtk.Menu()
                parent.set_submenu(submenu)
                if state:
                    item(submenu, state['status'][:200])
                    item(submenu, 'End sharing — return port locally',
                         lambda b=bus: self.command([cfg['systemctl'], '--user', 'stop', unit(b)]))
                else:
                    for target in cfg['recipients']:
                        item(submenu, 'Send to ' + target, lambda b=bus, t=target: self.start(b, t))
            if not found and not states:
                item(menu, 'No USB devices available')
            item(menu, 'Quit applet (sharing continues)', Gtk.main_quit)
            menu.show_all()
            self.indicator.set_menu(menu)
            self.indicator.set_title(f'USB sharing: {len(states)} selected ports')
            return True

        def dismiss(self):
            self.error = None
            self.refresh()

    app = Tray()
    Gtk.main()
    return app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('mode', nargs='?', default='tray', choices=['tray', 'session'])
    parser.add_argument('bus', nargs='?')
    parser.add_argument('target', nargs='?')
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text())
    if args.mode == 'session':
        unit(args.bus)
        session(cfg, args.bus, args.target)
    else:
        with (runtime() / 'tray.lock').open('w') as singleton:
            try:
                fcntl.flock(singleton, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            tray(cfg, args.config)


if __name__ == '__main__':
    main()
