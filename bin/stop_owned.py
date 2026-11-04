#!/usr/bin/python3
"""Stop only a process group positively recorded by DEX 3js."""
import json
import getpass
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

def group_members(group):
    listing = subprocess.run(["/bin/ps", "-axo", "pid=,pgid=,user=,stat="], check=True, capture_output=True, text=True).stdout
    return [line.split() for line in listing.splitlines() if len(line.split()) >= 4 and line.split()[1] == str(group)]

def leader_is_same_process(pid, start):
    rows = [row for row in group_members(pid) if row[0] == str(pid)]
    if not rows:
        return False
    current_start = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
    return current_start == start

def clear_matching_record():
    try:
        latest = json.loads(record_path.read_text())
        if latest.get("pid") == pid and latest.get("start") == started and latest.get("appBundleID") == "com.westkitty.dex3js":
            record_path.unlink()
    except (OSError, json.JSONDecodeError):
        pass

def clear_stale_record_without_signaling(reason):
    members = group_members(pgid)
    active = [member for member in members if "Z" not in member[3]]
    if not active:
        clear_matching_record()
        print(f"Cleared stale DEX process record ({reason}); no process was signaled.")
        raise SystemExit(0)
    print("Refusing stale-record cleanup: the recorded group still has active members; no process was signaled.", file=sys.stderr)
    raise SystemExit(2)

record_path = Path.home() / "Library/Application Support/DEX 3js/process.json"
if not record_path.exists():
    print("No DEX 3js project process is recorded.")
    raise SystemExit(0)
try:
    record = json.loads(record_path.read_text())
    pid = int(record["pid"])
    pgid = int(record["pgid"])
    cwd = str(Path(record["cwd"]).resolve(strict=True))
    executable = record["executable"]
    started = record["start"].strip()
    if record.get("version") != 1 or record.get("appBundleID") != "com.westkitty.dex3js" or pid <= 1 or pgid != pid:
        raise ValueError("ownership record identity is invalid")
    allowed = {f"/opt/homebrew/bin/{x}" for x in ("npm", "pnpm", "yarn", "bun")} | {f"/usr/local/bin/{x}" for x in ("npm", "pnpm", "yarn", "bun")}
    if executable not in allowed:
        raise ValueError("recorded executable is outside verified package-manager paths")
    ps = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "pgid=", "-o", "command="], check=False, capture_output=True, text=True)
    line = ps.stdout.strip()
    if ps.returncode != 0 or not line:
        clear_stale_record_without_signaling("leader is absent and the group has no active processes")
    actual_pgid, command = line.split(None, 1)
    current_start = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
    if current_start != started:
        clear_stale_record_without_signaling("the recorded PID now has a different start time")
    if int(actual_pgid) != pgid or Path(executable).name not in command or "run dev" not in command:
        raise ValueError("live process does not match the recorded DEX launch identity")
    start = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart="], check=True, capture_output=True, text=True).stdout.strip()
    if start != started:
        raise ValueError("process start time differs from the ownership record")
    cwd_out = subprocess.run(["/usr/sbin/lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], check=True, capture_output=True, text=True).stdout
    actual_cwd = next((line[1:] for line in cwd_out.splitlines() if line.startswith("n")), None)
    if actual_cwd != cwd:
        raise ValueError("live process working directory does not match the ownership record")
except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
    print(f"Refusing to stop an unverified process: {exc}", file=sys.stderr)
    raise SystemExit(2)

try:
    os.killpg(pgid, signal.SIGTERM)
except ProcessLookupError:
    print("Recorded DEX process group already exited.")
    raise SystemExit(0)
print(f"Sent SIGTERM to DEX-owned process group {pgid}; waiting up to 2 seconds.")
deadline = time.monotonic() + 2
remaining = False
while time.monotonic() < deadline:
    try:
        os.killpg(pgid, 0)
        remaining = True
        time.sleep(0.1)
    except ProcessLookupError:
        print("DEX-owned process group stopped.")
        clear_matching_record()
        raise SystemExit(0)
    except PermissionError:
        members = group_members(pgid)
        if members and all("Z" in member[3] for member in members):
            print("DEX process has exited; only zombie entries await reaping.")
            clear_matching_record()
            raise SystemExit(0)
        if not members or not leader_is_same_process(pid, started) or any(member[2] != getpass.getuser() for member in members):
            print("Refusing escalation: the original group leader is not present with the recorded identity.", file=sys.stderr)
            raise SystemExit(2)
        remaining = True
        time.sleep(0.1)
if remaining:
    members = group_members(pgid)
    if not members:
        print("DEX-owned process group stopped.")
        clear_matching_record()
        raise SystemExit(0)
    if all("Z" in member[3] for member in members):
        print("DEX process has exited; only zombie entries await reaping.")
        clear_matching_record()
        raise SystemExit(0)
    if not leader_is_same_process(pid, started) or any(member[2] != getpass.getuser() for member in members):
        print("Refusing escalation: remaining members do not retain the recorded process identity.", file=sys.stderr)
        raise SystemExit(2)
    try:
        os.killpg(pgid, signal.SIGKILL)
        print("Sent SIGKILL to remaining members of the verified DEX-owned process group.")
    except PermissionError:
        print("Refusing escalation: operating system denied access to the verified group.", file=sys.stderr)
        raise SystemExit(2)
    except ProcessLookupError:
        print("DEX-owned process group stopped.")
        clear_matching_record()
        raise SystemExit(0)

    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        members = group_members(pgid)
        if not members or all("Z" in member[3] for member in members):
            print("DEX-owned process group stopped.")
            clear_matching_record()
            raise SystemExit(0)
        time.sleep(0.1)
    print("SIGKILL was sent, but the process group has not disappeared; ownership record retained.", file=sys.stderr)
    raise SystemExit(2)
