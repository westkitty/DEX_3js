#!/usr/bin/python3
"""Exercise the CLI's exact-identity stop path against a disposable local dev server."""
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time

state = Path.home() / "Library/Application Support/DEX 3js/process.json"
if state.exists():
    raise SystemExit("Refusing to replace an existing DEX process record")
npm = shutil.which("npm")
if npm not in {"/opt/homebrew/bin/npm", "/usr/local/bin/npm"}:
    raise SystemExit("No npm executable in the launcher's verified paths")
probe = socket.socket()
probe.bind(("127.0.0.1", 0))
port = probe.getsockname()[1]
probe.close()
with tempfile.TemporaryDirectory(prefix="dex3js-stop-smoke-") as tmp:
    root = Path(tmp)
    (root / "package.json").write_text(json.dumps({"name":"dex3js-stop-smoke","scripts":{"dev":"node server.cjs"}}))
    (root / "server.cjs").write_text("const h=require('http');const s=h.createServer((q,r)=>r.end('ok'));s.listen(Number(process.env.DEX3JS_TEST_PORT),'127.0.0.1');setInterval(()=>{},1000);\n")
    log = open(root / "server.log", "w")
    proc = subprocess.Popen([npm, "run", "dev", "--", "--host", "127.0.0.1"], cwd=root, env={**os.environ, "DEX3JS_TEST_PORT":str(port)}, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
    try:
        # macOS may take several seconds to schedule a fresh Node process under load.
        for _ in range(300):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                if proc.poll() is not None:
                    raise RuntimeError(f"Disposable development server exited before readiness: {Path(log.name).read_text()}")
                time.sleep(0.1)
        else:
            raise RuntimeError(f"Disposable development server did not become ready: {Path(log.name).read_text()}")
        start = subprocess.run(["/bin/ps", "-p", str(proc.pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(json.dumps({"version":1,"pid":proc.pid,"pgid":proc.pid,"start":start,"cwd":str(root),"executable":npm,"appBundleID":"com.westkitty.dex3js"}, indent=2))
        state.chmod(0o600)
        stopper = Path(__file__).resolve().parents[1] / "bin/stop_owned.py"
        result = subprocess.run(["/usr/bin/python3", str(stopper)], capture_output=True, text=True, timeout=8)
        if result.returncode != 0:
            raise RuntimeError(f"stop helper failed ({result.returncode}): {result.stderr}{result.stdout}")
        proc.wait(timeout=3)
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                raise RuntimeError("Disposable server still accepts connections after stop")
        except OSError:
            pass
        print("PASS: DEX stop helper validated identity and stopped its disposable npm/Vite-style process group")
        print(result.stdout.strip())
    finally:
        if proc.poll() is None:
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait(timeout=3)
        log.close()
        try: state.unlink()
        except FileNotFoundError: pass

stopper = Path(__file__).resolve().parents[1] / "bin/stop_owned.py"

def write_record(pid, cwd, start):
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(json.dumps({"version":1,"pid":pid,"pgid":pid,"start":start,"cwd":str(cwd.resolve()),"executable":npm,"appBundleID":"com.westkitty.dex3js"}, indent=2))
    state.chmod(0o600)

with tempfile.TemporaryDirectory(prefix="dex3js-stale-stop-") as tmp:
    root = Path(tmp)
    stale = subprocess.Popen(["/bin/sleep", "30"], cwd=root, start_new_session=True)
    start = subprocess.run(["/bin/ps", "-p", str(stale.pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
    stale.terminate(); stale.wait(timeout=3)
    write_record(stale.pid, root, start)
    result = subprocess.run(["/usr/bin/python3", str(stopper)], capture_output=True, text=True, timeout=5)
    if result.returncode != 0 or "no process was signaled" not in result.stdout or state.exists():
        raise RuntimeError(f"stale record was not safely cleared: {result.returncode}: {result.stderr}{result.stdout}")
    print("PASS: an exited DEX leader's empty process group clears stale state without signaling")

with tempfile.TemporaryDirectory(prefix="dex3js-orphan-stop-") as tmp:
    root = Path(tmp)
    parent = subprocess.Popen(["/usr/bin/python3", "-c", "import subprocess,time; c=subprocess.Popen(['/bin/sleep','30']); print(c.pid,flush=True); time.sleep(30)"], cwd=root, start_new_session=True, stdout=subprocess.PIPE, text=True)
    child_pid = int(parent.stdout.readline().strip())
    start = subprocess.run(["/bin/ps", "-p", str(parent.pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
    parent.kill(); parent.wait(timeout=3)
    write_record(parent.pid, root, start)
    result = subprocess.run(["/usr/bin/python3", str(stopper)], capture_output=True, text=True, timeout=5)
    if result.returncode != 2 or "no process was signaled" not in result.stderr:
        raise RuntimeError(f"orphaned live group was not preserved safely: {result.returncode}: {result.stderr}{result.stdout}")
    os.kill(child_pid, 0)
    print("PASS: a live orphaned group is preserved and not signaled when its leader is gone")
    try: os.killpg(parent.pid, signal.SIGKILL)
    except ProcessLookupError: pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try: os.kill(child_pid, 0)
        except ProcessLookupError: break
        time.sleep(0.1)
    else: raise RuntimeError("could not clean the test-owned orphan group")
    try: state.unlink()
    except FileNotFoundError: pass
