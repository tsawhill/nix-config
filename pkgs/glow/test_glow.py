"""Local integration checks; requires Python, Rich, and rsync on PATH."""
import sys, os, subprocess, tempfile, pathlib, importlib.util, pty, select, time, signal
path = str(pathlib.Path(__file__).with_name('glow.py'))
spec = importlib.util.spec_from_file_location('glow', path)
m = importlib.util.module_from_spec(spec); sys.modules['glow']=m; spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    src=pathlib.Path(tmp)/'src'; src.mkdir()
    for name, n in [('big.iso', 2000000), ('small [bold]|test', 123), ('empty',0), ('new\nline',42)]:
        (src/name).write_bytes(b'x'*n)
    dest=pathlib.Path(tmp)/'dst'
    cmd=m.command(['-a',str(src)+'/',str(dest)])
    r=subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode==0, r.stderr
    d=m.Dashboard()
    for line in r.stdout.splitlines(): d.consume(line)
    assert d.completed==4, (d.completed,r.stdout)
    assert d.bytes==2000165, (d.bytes,r.stdout)
    for f in src.iterdir(): assert f.read_bytes()==(dest/f.name).read_bytes()
    print('Real rsync parser + contents: PASS', d.completed, d.bytes)
    dry=pathlib.Path(tmp)/'dry'
    r=subprocess.run([sys.executable,path,'-an',str(src)+'/',str(dry)],capture_output=True,text=True)
    assert r.returncode==0 and not dry.exists()
    assert '@@RSYNC_GLOW@@' not in r.stdout
    print('Dry run / pipe fallback: PASS')
    def terminal_run(arguments, cancel=False):
        master, slave=pty.openpty()
        proc=subprocess.Popen([sys.executable,path,*arguments],stdout=slave,stderr=slave,env={**os.environ,'TERM':'xterm-256color'})
        os.close(slave); output=b''; start=time.monotonic(); sent=False
        while time.monotonic()-start<15:
            if cancel and not sent and time.monotonic()-start>1:
                proc.send_signal(signal.SIGINT); sent=True
            if select.select([master],[],[],0.1)[0]:
                try: output+=os.read(master,65536)
                except OSError: break
        if proc.poll() is None: proc.kill()
        code=proc.wait(); os.close(master)
        return code,output
    code,out=terminal_run(['-a',str(src)+'/',str(pathlib.Path(tmp)/'tty')])
    assert code==0 and b'COMPLETE' in out and b'TRANSFER DECK' in out, (code,out[-1000:])
    print('Real terminal dashboard: PASS')
    code,out=terminal_run(['-a',str(src/'missing'),str(dest)])
    assert code==23 and b'FAILED' in out, (code,out[-1000:])
    print('Error exit preserved: PASS')
    # Exercise rsync's remote-shell path without contacting a real host.
    remote_shell = pathlib.Path(tmp) / 'ssh-failure'
    remote_shell.write_text(f'#!{sys.executable}\nimport sys\nsys.stderr.write("Permission denied (publickey).\\n")\nsys.exit(255)\n')
    remote_shell.chmod(0o755)
    code,out=terminal_run(['-rltDP','-e',str(remote_shell),str(src)+'/', 'example.invalid:destination/'])
    assert code==255, (code,out[-2000:])
    final=out[out.rfind(b'FAILED'):]
    assert b'Permission denied (publickey).' in final and b'SSH / rsync diagnostics' in final, final
    assert b'discovering files' not in final, final
    print('SSH failure diagnostics survive final dashboard: PASS')
    code,out=terminal_run(['-a','--bwlimit=100',str(src)+'/',str(pathlib.Path(tmp)/'cancel')],True)
    assert code==130, (code,out[-1000:])
    print('Cancellation: PASS')
