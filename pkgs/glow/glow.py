"""A bounded-memory Rich dashboard for one ordinary rsync process."""
import codecs
from collections import deque
from dataclasses import dataclass
import os
import re
import selectors
import signal
import subprocess
import sys
import time

from rich import box
from rich.console import Console, Group
from rich.panel import Panel
from rich.progress_bar import ProgressBar
from rich.table import Table
from rich.text import Text
from rich.live import Live

MARKER = '@@RSYNC_GLOW@@'
PROGRESS = re.compile(r'^\s*([\d,]+)\s+(\d+)%\s+(\S+)\s+(\S+)(.*)$')
CHECKED = re.compile(r'(ir|to)-chk=(\d+)/(\d+)')


def safe(value):
    return ''.join(c if c.isprintable() else '?' for c in value)


def size(value):
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if value < 1024 or unit == 'TiB':
            return f'{value:.1f} {unit}'
        value /= 1024


@dataclass
class File:
    name: str
    total: int
    done: int = 0
    complete: bool = False


class Dashboard:
    def __init__(self):
        self.files = deque(maxlen=64)
        self.events = deque(maxlen=4)
        self.current = None
        self.completed = 0
        self.bytes = 0
        self.speed = '—'
        self.eta = '—'
        self.checked = 0
        self.total = 0
        self.scanning = True
        self.started = time.monotonic()
        self.samples = deque(maxlen=36)
        self.last_bytes = 0
        self.last_sample = self.started
        self.status = 'CONNECTING / SCANNING'

    def consume(self, line):
        if line.startswith(MARKER + '|'):
            fields = line.split('|', 3)
            if len(fields) != 4:
                return
            _, item, length, name = fields
            if item[:1] in ('<', '>') and item[1:2] == 'f' and length.strip().isdigit():
                self.current = File(safe(name), int(length))
                self.files.append(self.current)
                self.status = 'TRANSFERRING'
            else:
                self.events.append(safe(item + '  ' + name))
            return
        match = PROGRESS.match(line)
        if match and self.current is not None:
            amount, percent, self.speed, self.eta, tail = match.groups()
            amount = int(amount.replace(',', ''))
            self.bytes += max(0, amount - self.current.done)
            self.current.done = amount
            checked = CHECKED.search(tail)
            if checked:
                kind, remaining, total = checked.groups()
                self.total = int(total)
                self.checked = self.total - int(remaining)
                self.scanning = kind == 'ir'
            if 'xfr#' in tail and not self.current.complete:
                self.current.complete = True
                self.completed += 1
                self.eta = '—'
            return
        if line.strip():
            self.events.append(safe(line.strip()))

    def render(self, console):
        now = time.monotonic()
        if now - self.last_sample >= 0.5:
            self.samples.append(max(0, self.bytes - self.last_bytes) / (now - self.last_sample))
            self.last_bytes, self.last_sample = self.bytes, now
        peak = max(self.samples, default=1) or 1
        trace = ''.join('▁▂▃▄▅▆▇█'[min(7, int(n / peak * 7))] for n in self.samples)
        elapsed = int(now - self.started)
        header = Text('◈  GLOW', style='bold bright_cyan')
        header.append('   /   ' + self.status, style='bold bright_magenta')
        metrics = Text(f'{size(self.bytes)} processed   •   {self.completed} files   •   {elapsed // 60:02}:{elapsed % 60:02} elapsed\n', style='white')
        metrics.append(f'{self.speed}   {trace}', style='bright_cyan')
        metrics.append(f'   file ETA {self.eta}', style='bright_magenta')
        label = Text(f'FILE LIST CHECKED   {self.checked:,} / {self.total:,}', style='dim')
        if self.scanning:
            label.append('   discovering files…', style='bright_magenta')
        overview = Group(header, Text(''), metrics, Text(''), label,
                         ProgressBar(total=self.total or None, completed=self.checked,
                                     pulse=not self.total, complete_style='cyan', finished_style='bright_cyan'))
        table = Table(box=None, expand=True, padding=(0, 1))
        table.add_column('', width=1)
        table.add_column('FILE', ratio=3, overflow='ellipsis', no_wrap=True)
        table.add_column('PROGRESS', ratio=2)
        table.add_column('%', justify='right', width=4)
        table.add_column('SIZE', justify='right', width=18)
        count = max(1, min(8, console.height - 19))
        for f in list(self.files)[-count:]:
            color = 'bright_cyan' if f.complete else 'bright_magenta'
            table.add_row(Text('✓' if f.complete else '›', style=color), Text(f.name, style='dim' if f.complete else 'bold white'),
                          ProgressBar(total=max(1, f.total), completed=max(1, f.total) if f.complete else f.done,
                                      complete_style=color, finished_style=color),
                          Text('100%' if f.complete else f'{min(100, f.done * 100 // max(1, f.total))}%', style=color),
                          Text(f'{size(f.done)} / {size(f.total)}', style=color))
        if not self.files:
            table.add_row('', Text('Waiting for files…', style='dim'), '', '', '')
        events = Text('\n'.join(self.events), style='dim', overflow='ellipsis', no_wrap=True)
        return Group(Panel(overview, border_style='bright_cyan', box=box.ROUNDED),
                     Panel(table, title='[bold bright_magenta]TRANSFER DECK', border_style='magenta', box=box.ROUNDED),
                     events, Text('  rsync engine  •  Ctrl+C cancel  •  tmux detach keeps running', style='dim'))


def command(args):
    # Insert before -- so dash-prefixed operands retain their meaning.
    index = args.index('--') if '--' in args else len(args)
    return ['rsync', *args[:index], '--no-human-readable', '--outbuf=N',
            '--info=progress1,name1', f'--out-format={MARKER}|%i|%l|%n', *args[index:]]


def main():
    args = sys.argv[1:]
    if not args or args == ['--help']:
        print('glow — neon rsync dashboard\n\nUsage: glow [rsync options] SOURCE... DEST\n'
              'Example: glow -a --partial /source/ user@host:/destination/\n\n'
              'Uses ordinary rsync semantics; no archive, deletion, or resume flags are added.\n'
              'File bars show logical bytes processed, not network bytes.\n'
              'Overall bar counts file-list entries checked; totals may grow during scanning.\n'
              'Dry runs, redirected output, and quiet mode use plain rsync output.\n'
              'Dashboard owns --info, --out-format, --outbuf and human-readable formatting.')
        return 0
    options = args[:args.index('--')] if '--' in args else args
    plain = (not sys.stdout.isatty() or os.environ.get('TERM') == 'dumb' or
             any(a in ('--dry-run', '--quiet', '--help', '--version', '--list-only', '--daemon', '--server') or
                 (a.startswith('-') and not a.startswith('--') and any(c in a[1:] for c in 'nqV'))
                 for a in options))
    if plain:
        os.execvp('rsync', ['rsync', *args])
    console = Console(highlight=False)
    dashboard = Dashboard()
    # Keep stdin and the controlling TTY for SSH authentication. Child writes
    # bypass Rich's Python stderr redirect, so explicitly capture diagnostics.
    proc = subprocess.Popen(command(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env={**os.environ, 'LC_ALL': 'C'})
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ, 'stdout')
    selector.register(proc.stderr, selectors.EVENT_READ, 'stderr')
    decoders = {name: codecs.getincrementaldecoder('utf-8')(errors='replace')
                for name in ('stdout', 'stderr')}
    diagnostics = ''
    pending = ''
    cancelled = False
    previous = {}

    def stop(signum, frame):
        raise KeyboardInterrupt

    for sig in (signal.SIGTERM, signal.SIGHUP):
        previous[sig] = signal.signal(sig, stop)
    try:
        with Live(dashboard.render(console), console=console, auto_refresh=False) as live:
            # Explicit refresh avoids a UI thread racing parser state.
            while selector.get_map():
                for key, _ in selector.select(timeout=0.1):
                    data = os.read(key.fd, 65536)
                    decoded = decoders[key.data].decode(data, final=not data)
                    if not data:
                        selector.unregister(key.fileobj)
                    if key.data == 'stderr':
                        diagnostics = (diagnostics + decoded)[-65536:]
                        if decoded:
                            # Suspend painting while a diagnostic or prompt is
                            # written, including prompts without a newline.
                            live.stop()
                            console.print(Text(''.join(c if c.isprintable() or c in '\n\t' else '?' for c in decoded)), end='')
                        continue
                    pending += decoded
                    records = re.split(r'[\r\n]', pending)
                    pending = records.pop()
                    for line in records:
                        dashboard.consume(line)
                    if not data:
                        dashboard.consume(pending)
                # No repaint during connection/authentication: SSH may write
                # password/host-key prompts directly to /dev/tty.
                if dashboard.current is not None and proc.poll() is None:
                    live.start()
                    live.update(dashboard.render(console), refresh=True)
            code = proc.wait()
            dashboard.status = 'COMPLETE' if code == 0 else f'FAILED / EXIT {code}'
            dashboard.scanning = False
            if code == 0:
                dashboard.scanning = False
                dashboard.checked = dashboard.total
            live.start()
            live.update(dashboard.render(console), refresh=True)
        if diagnostics.strip():
            console.print(Panel(Text(''.join(c if c.isprintable() or c in '\n\t' else '?' for c in diagnostics).rstrip()),
                                title='SSH / rsync diagnostics', border_style='red' if code else 'yellow'))
    except KeyboardInterrupt:
        cancelled = True
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        console.print('Transfer cancelled.', style='yellow')
    finally:
        selector.close()
        proc.stdout.close()
        proc.stderr.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    return 130 if cancelled else (proc.returncode if proc.returncode >= 0 else 128 - proc.returncode)


if __name__ == '__main__':
    sys.exit(main())
