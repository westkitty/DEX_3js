#!/usr/bin/env python3
"""Run the native Store lifecycle smoke with disposable HOME and loopback port."""
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: run_store_lifecycle_smoke.py <compiled-smoke>")

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]

with tempfile.TemporaryDirectory(prefix="dex3js-store-smoke-home-") as raw_home:
    home = Path(raw_home)
    env = {**os.environ, "HOME": str(home), "CFFIXED_USER_HOME": str(home), "DEX3JS_TEST_PORT": str(port)}
    result = subprocess.run([sys.argv[1]], env=env, check=False)
    raise SystemExit(result.returncode)
